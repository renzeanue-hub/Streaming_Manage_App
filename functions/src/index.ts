import {onSchedule} from "firebase-functions/v2/scheduler";
import {defineSecret} from "firebase-functions/params";
import {initializeApp} from "firebase-admin/app";
import {getFirestore, Timestamp} from "firebase-admin/firestore";

initializeApp();

const db = getFirestore();
const YOUTUBE_API_KEY = defineSecret("YOUTUBE_API_KEY");

// ---- Config ----
type StreamerId = "rara" | "chino" | "neffy" | "vitte";

const STREAMERS: Array<{id: StreamerId; handle: string}> = [
  {id: "rara", handle: "v-rara"},
  {id: "chino", handle: "v-chino"},
  {id: "neffy", handle: "v-neffy"},
  {id: "vitte", handle: "v-vitte"},
];

const MATCH_WINDOW_MINUTES = 20;

// streamer_meta キャッシュの有効期限（24時間）
const META_TTL_MS = 24 * 60 * 60 * 1000;

// ---- YouTube minimal types ----
type YouTubeVideosItem = {
  id: string;
  snippet?: {
    title?: string;
    liveBroadcastContent?: "none" | "upcoming" | "live";
  };
  liveStreamingDetails?: {
    scheduledStartTime?: string;
    actualStartTime?: string;
    actualEndTime?: string;
  };
  status?: {
    privacyStatus?: string;
    uploadStatus?: string;
  };
};

// ---- Firestore doc shapes ----
type StreamerMeta = {
  channelId: string;
  uploadsPlaylistId: string;
  cachedAt: FirebaseFirestore.Timestamp;
};

type StreamDoc = {
  streamerId: string;
  title: string;
  startAt: FirebaseFirestore.Timestamp;
  youtubeVideoId?: string | null;
  youtubeWatchUrl?: string | null;
  archiveUrl?: string | null;
  status?: string | null;
  syncedStartAt?: FirebaseFirestore.Timestamp | null;
  endAt?: FirebaseFirestore.Timestamp | null;
  updatedAt?: FirebaseFirestore.Timestamp | null;
};

// ---- Utils ----
function minutesDiff(a: Date, b: Date): number {
  return Math.abs(a.getTime() - b.getTime()) / 60000;
}

function watchUrl(videoId: string): string {
  return `https://www.youtube.com/watch?v=${videoId}`;
}

async function ytGetJson<T>(url: string): Promise<T> {
  const res = await fetch(url);
  if (!res.ok) {
    const text = await res.text();
    throw new Error(
      `YouTube API error: ${res.status} ${res.statusText} :: ${text}`
    );
  }
  return (await res.json()) as T;
}

// ---- Firestore キャッシュ付き channelId / uploadsPlaylistId 解決 ----
// channels.list を 1unit で叩いて channelId と uploadsPlaylistId を両方取得し
// streamer_meta/{streamerId} にキャッシュ。TTL 内は Firestore から読むだけ（0 unit）
async function resolveStreamerMeta(
  apiKey: string,
  streamerId: string,
  handle: string
): Promise<{channelId: string; uploadsPlaylistId: string}> {
  const ref = db.collection("streamer_meta").doc(streamerId);
  const snap = await ref.get();

  if (snap.exists) {
    const cached = snap.data() as StreamerMeta;
    const ageMs = Date.now() - cached.cachedAt.toMillis();
    if (ageMs < META_TTL_MS) {
      console.log(`[meta] cache hit: ${streamerId}`);
      return {
        channelId: cached.channelId,
        uploadsPlaylistId: cached.uploadsPlaylistId,
      };
    }
  }

  // キャッシュ切れ or 初回 → YouTube API を叩く（1 unit）
  console.log(`[meta] fetching from YouTube API: @${handle}`);
  const url =
    "https://www.googleapis.com/youtube/v3/channels" +
    `?part=id,contentDetails&forHandle=${encodeURIComponent(handle)}` +
    `&key=${encodeURIComponent(apiKey)}`;

  const data = await ytGetJson<{
    items?: Array<{
      id: string;
      contentDetails?: {relatedPlaylists?: {uploads?: string}};
    }>;
  }>(url);

  const item = data.items?.[0];
  if (!item?.id) throw new Error(`Cannot resolve channelId for @${handle}`);

  const channelId = item.id;
  const uploadsPlaylistId = item.contentDetails?.relatedPlaylists?.uploads;
  if (!uploadsPlaylistId) {
    throw new Error(`Cannot resolve uploadsPlaylistId for @${handle}`);
  }

  await ref.set({
    channelId,
    uploadsPlaylistId,
    cachedAt: Timestamp.now(),
  } satisfies StreamerMeta);

  return {channelId, uploadsPlaylistId};
}

// ---- playlistItems.list で最新動画 ID を取得（1 unit）----
// search.list(100 unit) の代わりにこちらを使う
async function fetchUploadedVideoIds(
  apiKey: string,
  uploadsPlaylistId: string,
  maxResults = 10
): Promise<string[]> {
  const url =
    "https://www.googleapis.com/youtube/v3/playlistItems" +
    `?part=snippet&playlistId=${encodeURIComponent(uploadsPlaylistId)}` +
    `&maxResults=${maxResults}&key=${encodeURIComponent(apiKey)}`;

  const data = await ytGetJson<{
    items?: Array<{snippet?: {resourceId?: {videoId?: string}}}>;
  }>(url);

  const ids =
    data.items
      ?.map((it) => it.snippet?.resourceId?.videoId)
      .filter((v): v is string => !!v) ?? [];

  return Array.from(new Set(ids));
}

// ---- videos.list で詳細取得（件数 ÷ 50 unit）----
async function fetchVideoDetails(
  apiKey: string,
  videoIds: string[]
): Promise<YouTubeVideosItem[]> {
  if (videoIds.length === 0) return [];

  const chunks: string[][] = [];
  for (let i = 0; i < videoIds.length; i += 50) {
    chunks.push(videoIds.slice(i, i + 50));
  }

  const all: YouTubeVideosItem[] = [];
  for (const chunk of chunks) {
    const url =
      "https://www.googleapis.com/youtube/v3/videos" +
      `?part=snippet,liveStreamingDetails,status` +
      `&id=${encodeURIComponent(chunk.join(","))}` +
      `&key=${encodeURIComponent(apiKey)}`;

    const data = await ytGetJson<{items?: YouTubeVideosItem[]}>(url);
    all.push(...(data.items ?? []));
  }
  return all;
}

// ---- Firestore から近日の配信枠を取得 ----
async function loadPlannedStreams(): Promise<Array<{id: string; data: StreamDoc}>> {
  const now = new Date();
  const from = new Date(now.getTime() - 24 * 60 * 60 * 1000);
  const to = new Date(now.getTime() + 14 * 24 * 60 * 60 * 1000);

  const snap = await db
    .collection("streams")
    .where("startAt", ">=", Timestamp.fromDate(from))
    .where("startAt", "<=", Timestamp.fromDate(to))
    .get();

  return snap.docs.map((d) => ({id: d.id, data: d.data() as StreamDoc}));
}

function deriveStatus(v: YouTubeVideosItem): "scheduled" | "live" | "ended" {
  const d = v.liveStreamingDetails;
  if (d?.actualEndTime) return "ended";
  if (d?.actualStartTime) return "live";
  if (v.snippet?.liveBroadcastContent === "live") return "live";
  return "scheduled";
}

// ---- メイン scheduled function ----
export const syncYoutube = onSchedule(
  {
    schedule: "every 15 minutes",
    timeZone: "Asia/Tokyo",
    secrets: [YOUTUBE_API_KEY],
    region: "asia-northeast1",
  },
  async () => {
    const apiKey = YOUTUBE_API_KEY.value();

    // 1) channelId / uploadsPlaylistId を解決（Firestore キャッシュ優先）
    const metaByStreamer: Record<string, {channelId: string; uploadsPlaylistId: string}> = {};
    for (const s of STREAMERS) {
      metaByStreamer[s.id] = await resolveStreamerMeta(apiKey, s.id, s.handle);
    }

    // 2) playlistItems で各ストリーマーの最新動画を取得（1 unit × 4 人）
    //    liveBroadcastContent が upcoming / live のものだけ残す
    const candidatesByStreamer: Record<string, YouTubeVideosItem[]> = {};
    for (const s of STREAMERS) {
      const {uploadsPlaylistId} = metaByStreamer[s.id];

      // まず ID だけ取得（1 unit）
      const videoIds = await fetchUploadedVideoIds(apiKey, uploadsPlaylistId, 10);

      // 詳細を一括取得（1 unit / 最大 50 件）
      const details = await fetchVideoDetails(apiKey, videoIds);

      // upcoming または live のみに絞る
      candidatesByStreamer[s.id] = details.filter((v) => {
        const lbc = v.snippet?.liveBroadcastContent;
        return lbc === "upcoming" || lbc === "live";
      });

      console.log(
        `[sync] ${s.id}: candidates=${candidatesByStreamer[s.id].length}`
      );
    }

    // 3) Firestore から近日の配信枠を取得
    const streams = await loadPlannedStreams();

    // 4) マッチング & ステータス更新
    const batch = db.batch();
    let touched = 0;

    for (const s of streams) {
      const ref = db.collection("streams").doc(s.id);
      const data = s.data;
      const streamerId = data.streamerId as StreamerId;
      const plannedStart = data.startAt.toDate();

      // A) 既にリンク済み → ステータス・タイトル・終了時刻を同期
      if (data.youtubeVideoId) {
        // ← バグ修正: v を宣言してから使う
        const [v] = await fetchVideoDetails(apiKey, [data.youtubeVideoId]);
        if (!v) continue;

        const d = v.liveStreamingDetails;

        console.log("[sync] already linked", {
          streamId: s.id,
          videoId: v.id,
          scheduled: d?.scheduledStartTime,
          actualStart: d?.actualStartTime,
          actualEnd: d?.actualEndTime,
        });

        const patch: Record<string, unknown> = {
          status: deriveStatus(v),
          youtubeWatchUrl: watchUrl(v.id),
          archiveUrl: watchUrl(v.id),
          updatedAt: Timestamp.now(),
        };

        if (v.snippet?.title) patch.title = v.snippet.title;
        if (d?.scheduledStartTime) {
          patch.syncedStartAt = Timestamp.fromDate(new Date(d.scheduledStartTime));
        }
        if (d?.actualEndTime) {
          patch.endAt = Timestamp.fromDate(new Date(d.actualEndTime));
        }

        batch.update(ref, patch);
        touched++;
        continue;
      }

      // B) 未リンク → 時間窓内に候補が 1 件だけなら自動リンク
      const candidates = candidatesByStreamer[streamerId] ?? [];
      const matched = candidates.filter((v) => {
        const d = v.liveStreamingDetails;
        const ts = d?.scheduledStartTime ?? d?.actualStartTime;
        if (!ts) return false;
        return minutesDiff(new Date(ts), plannedStart) <= MATCH_WINDOW_MINUTES;
      });

      console.log(
        `[sync] unlinked ${s.id}: matched=${matched.length}`
      );

      if (matched.length === 1) {
        const v = matched[0];
        const d = v.liveStreamingDetails;

        const patch: Record<string, unknown> = {
          youtubeVideoId: v.id,
          youtubeWatchUrl: watchUrl(v.id),
          status: deriveStatus(v),
          updatedAt: Timestamp.now(),
        };

        if (v.snippet?.title) patch.title = v.snippet.title;
        if (d?.scheduledStartTime) {
          patch.syncedStartAt = Timestamp.fromDate(new Date(d.scheduledStartTime));
        }

        batch.update(ref, patch);
        touched++;
      }
    }

    if (touched > 0) await batch.commit();
    console.log(`syncYoutube done. updatedDocs=${touched}`);

    // C) どの stream にもマッチしなかった候補 → 自動で新規作成
    const linkedVideoIds = new Set(
      streams.map((s) => s.data.youtubeVideoId).filter(Boolean)
    );

    for (const s of STREAMERS) {
      const candidates = candidatesByStreamer[s.id] ?? [];
      for (const v of candidates) {
        if (linkedVideoIds.has(v.id)) continue; // 既にリンク済みはスキップ

        const d = v.liveStreamingDetails;
        const ts = d?.scheduledStartTime ?? d?.actualStartTime;
        if (!ts) continue;

        const newRef = db.collection("streams").doc();
        batch.set(newRef, {
          streamerId: s.id,
          title: v.snippet?.title ?? '(タイトル未取得)',
          startAt: Timestamp.fromDate(new Date(ts)),
          youtubeVideoId: v.id,
          youtubeWatchUrl: watchUrl(v.id),
          status: deriveStatus(v),
          source: 'youtube_auto', // 自動追加フラグ
          updatedAt: Timestamp.now(),
        });
        touched++;
      }
    }
  }
);

