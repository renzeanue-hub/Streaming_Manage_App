import {onSchedule} from "firebase-functions/v2/scheduler";
import {defineSecret} from "firebase-functions/params";
import {initializeApp} from "firebase-admin/app";
import {getFirestore, Timestamp} from "firebase-admin/firestore";

initializeApp();

const db = getFirestore();
const YOUTUBE_API_KEY = defineSecret("YOUTUBE_API_KEY");

// ---- Config (fixed 4 streamers) ----
type StreamerId = "rara" | "chino" | "neffy" | "vitte";

const STREAMERS: Array<{
  id: StreamerId;
  handle: string; // without '@'
}> = [
  {id: "rara", handle: "v-rara"},
  {id: "chino", handle: "v-chino"},
  {id: "neffy", handle: "v-neffy"},
  {id: "vitte", handle: "v-vitte"},
];

const MATCH_WINDOW_MINUTES = 20;

// ---- YouTube minimal types ----
type YouTubeSearchItem = {
  id: { kind: string; videoId?: string };
};

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
    throw new Error(`YouTube API error: ${res.status} ${res.statusText} :: ${text}`);
  }
  return (await res.json()) as T;
}

// Resolve @handle -> channelId using channels.list?forHandle=...
async function resolveChannelIdForHandle(apiKey: string, handle: string): Promise<string> {
  const url =
    "https://www.googleapis.com/youtube/v3/channels" +
    `?part=id&forHandle=${encodeURIComponent(handle)}&key=${encodeURIComponent(apiKey)}`;

  const data = await ytGetJson<{ items?: Array<{ id: string }> }>(url);
  const id = data.items?.[0]?.id;
  if (!id) throw new Error(`Unable to resolve channelId for handle @${handle}`);
  return id;
}

// Search upcoming/live videos for a channel
async function searchVideos(
  apiKey: string,
  channelId: string,
  eventType: "upcoming" | "live"
): Promise<string[]> {
  const url =
    "https://www.googleapis.com/youtube/v3/search" +
    `?part=id&channelId=${encodeURIComponent(channelId)}` +
    `&eventType=${encodeURIComponent(eventType)}` +
    "&type=video&maxResults=10&order=date" +
    `&key=${encodeURIComponent(apiKey)}`;

  const data = await ytGetJson<{ items?: YouTubeSearchItem[] }>(url);
  const ids =
    data.items
      ?.map((it) => it.id.videoId)
      .filter((v): v is string => !!v) ?? [];
  return Array.from(new Set(ids));
}

async function fetchVideoDetails(apiKey: string, videoIds: string[]): Promise<YouTubeVideosItem[]> {
  if (videoIds.length === 0) return [];

  // videos.list supports up to 50 ids
  const chunks: string[][] = [];
  for (let i = 0; i < videoIds.length; i += 50) chunks.push(videoIds.slice(i, i + 50));

  const all: YouTubeVideosItem[] = [];
  for (const chunk of chunks) {
    const url =
      "https://www.googleapis.com/youtube/v3/videos" +
      `?part=snippet,liveStreamingDetails,status&id=${encodeURIComponent(chunk.join(","))}` +
      `&key=${encodeURIComponent(apiKey)}`;

    const data = await ytGetJson<{ items?: YouTubeVideosItem[] }>(url);
    all.push(...(data.items ?? []));
  }
  return all;
}

// Firestore stream doc shape (partial)
type StreamDoc = {
  streamerId: string;
  title: string;
  startAt: FirebaseFirestore.Timestamp; // planned start
  youtubeVideoId?: string | null;
  youtubeWatchUrl?: string | null;
  archiveUrl?: string | null;
  status?: string | null;
  syncedStartAt?: FirebaseFirestore.Timestamp | null;
  endAt?: FirebaseFirestore.Timestamp | null;
  updatedAt?: FirebaseFirestore.Timestamp | null;
};

async function loadPlannedStreams(): Promise<Array<{ id: string; data: StreamDoc }>> {
  // Look at near-term window to reduce work:
  // planned start between -1 day and +14 days
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
  // fallback
  if (v.snippet?.liveBroadcastContent === "live") return "live";
  return "scheduled";
}

export const syncYoutube = onSchedule(
  {
    schedule: "every 15 minutes",
    timeZone: "Asia/Tokyo",
    secrets: [YOUTUBE_API_KEY],
    region: "asia-northeast1",
  },
  async () => {
    const apiKey = YOUTUBE_API_KEY.value();

    // 1) Resolve channelIds
    const channelIdsByStreamer: Record<string, string> = {};
    for (const s of STREAMERS) {
      channelIdsByStreamer[s.id] = await resolveChannelIdForHandle(apiKey, s.handle);
    }

    // 2) Collect candidate videos per streamer (upcoming+live)
    const candidatesByStreamer: Record<string, YouTubeVideosItem[]> = {};
    for (const s of STREAMERS) {
      const channelId = channelIdsByStreamer[s.id];

      const upcomingIds = await searchVideos(apiKey, channelId, "upcoming");
      const liveIds = await searchVideos(apiKey, channelId, "live");
      const ids = Array.from(new Set([...upcomingIds, ...liveIds]));

      const details = await fetchVideoDetails(apiKey, ids);

      // Keep only videos that have scheduledStartTime (needed for matching)
      candidatesByStreamer[s.id] = details.filter(
        (v) => !!v.liveStreamingDetails?.scheduledStartTime || !!v.liveStreamingDetails?.actualStartTime
      );
    }

    // 3) Load streams from Firestore
    const streams = await loadPlannedStreams();

    // 4) Match planned streams without youtubeVideoId
    // and also sync streams with youtubeVideoId
    const batch = db.batch();
    let touched = 0;

    for (const s of streams) {
      const ref = db.collection("streams").doc(s.id);
      const data = s.data;

      const streamerId = data.streamerId as StreamerId;
      const plannedStart = data.startAt.toDate();
      console.log(
        `[syncYoutube] ${s.id} streamerId=${streamerId} candidates=${(candidatesByStreamer[streamerId] ?? []).length}`
      );

      // A) If already linked -> sync status/time/title/end/archive
      if (data.youtubeVideoId) {
        const [v] = await fetchVideoDetails(apiKey, [data.youtubeVideoId]);
        if (!v) continue;

        const d = v.liveStreamingDetails;
        const patch: Record<string, any> = {
          status: deriveStatus(v),
          youtubeWatchUrl: watchUrl(v.id),
          archiveUrl: watchUrl(v.id), // same watch URL works as archive usually
          updatedAt: Timestamp.now(),
        };

        if (v.snippet?.title) patch.title = v.snippet.title;
        if (d?.scheduledStartTime) patch.syncedStartAt = Timestamp.fromDate(new Date(d.scheduledStartTime));
        if (d?.actualEndTime) patch.endAt = Timestamp.fromDate(new Date(d.actualEndTime));

        batch.update(ref, patch);
        touched++;
        continue;
      }

      // B) Not linked -> auto-link if exactly 1 candidate in time window
      const candidates = candidatesByStreamer[streamerId] ?? [];
      const matched = candidates.filter((v) => {
        const d = v.liveStreamingDetails;
        const ts = d?.scheduledStartTime ?? d?.actualStartTime;
        if (!ts) return false;
        const start = new Date(ts);
        return minutesDiff(start, plannedStart) <= MATCH_WINDOW_MINUTES;
      });

      if (matched.length === 1) {
        const v = matched[0];
        const d = v.liveStreamingDetails;

        const patch: Record<string, any> = {
          youtubeVideoId: v.id,
          youtubeWatchUrl: watchUrl(v.id),
          status: deriveStatus(v),
          updatedAt: Timestamp.now(),
        };

        if (v.snippet?.title) patch.title = v.snippet.title;
        if (d?.scheduledStartTime) patch.syncedStartAt = Timestamp.fromDate(new Date(d.scheduledStartTime));

        batch.update(ref, patch);
        touched++;
      }
    }

    if (touched > 0) {
      await batch.commit();
    }

    console.log(`syncYoutube done. updatedDocs=${touched}`);
  }
);
