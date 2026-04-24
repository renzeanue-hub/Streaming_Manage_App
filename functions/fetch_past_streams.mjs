// fetch_past_streams.mjs
//
// 使い方:
//   JSONに書き出すだけ:
//     node fetch_past_streams.mjs v-rara
//     node fetch_past_streams.mjs v-rara --out rara.json
//
//   Firestoreに直接インポート:
//     node fetch_past_streams.mjs v-rara --import
//     node fetch_past_streams.mjs --import-all   ← 4人まとめて
//
// 事前準備:
//   set YOUTUBE_API_KEY=AIza...                      (cmd)
//   $env:YOUTUBE_API_KEY="AIza..."                   (PowerShell)
//
//   Firestoreインポートを使う場合は serviceAccountKey.json を
//   このファイルと同じディレクトリに置いてください
//   (Firebase Console → プロジェクトの設定 → サービスアカウント → 新しい秘密鍵を生成)

import { writeFileSync, existsSync } from "fs";
import { createRequire } from "module";
const require = createRequire(import.meta.url);

const API_KEY = process.env.YOUTUBE_API_KEY;
if (!API_KEY) {
  console.error("❌ YOUTUBE_API_KEY が設定されていません");
  process.exit(1);
}

// ---- ハンドル → streamerId マッピング ----
const HANDLE_TO_ID = {
  "v-rara":  "rara",
  "v-chino": "chino",
  "v-neffy": "neffy",
  "v-vitte": "vitte",
};

// ---- 引数パース ----
const args = process.argv.slice(2);
const importAll = args.includes("--import-all");
const doImport = args.includes("--import") || importAll;

let handles = [];
if (importAll) {
  handles = Object.keys(HANDLE_TO_ID);
} else {
  const handle = args[0];
  if (!handle || handle.startsWith("--")) {
    console.error("❌ handle を指定してください (例: v-rara) または --import-all");
    process.exit(1);
  }
  handles = [handle];
}

const outIndex = args.indexOf("--out");
const outFile = outIndex !== -1 ? args[outIndex + 1] : null;

// ---- Firestore 初期化（--import 時のみ）----
let db = null;
if (doImport) {
  const KEY_PATH = "./serviceAccountKey.json";
  if (!existsSync(KEY_PATH)) {
    console.error(`❌ ${KEY_PATH} が見つかりません`);
    console.error("   Firebase Console → プロジェクトの設定 → サービスアカウント → 新しい秘密鍵を生成");
    process.exit(1);
  }
  const admin = require("firebase-admin");
  const serviceAccount = require(KEY_PATH);
  if (!admin.apps.length) {
    admin.initializeApp({
      credential: admin.credential.cert(serviceAccount),
    });
  }
  db = admin.firestore();
  console.log("✅ Firestore 接続OK\n");
}

// ---- YouTube API helpers ----
async function ytGet(url) {
  const res = await fetch(url);
  if (!res.ok) {
    const text = await res.text();
    throw new Error(`YouTube API error: ${res.status} :: ${text}`);
  }
  return res.json();
}

async function resolveChannel(handle) {
  const url =
    `https://www.googleapis.com/youtube/v3/channels` +
    `?part=id,snippet,contentDetails&forHandle=${encodeURIComponent(handle)}&key=${API_KEY}`;
  const data = await ytGet(url);
  const item = data.items?.[0];
  if (!item) throw new Error(`@${handle} のチャンネルが見つかりません`);
  return {
    channelId: item.id,
    channelTitle: item.snippet?.title ?? handle,
    uploadsPlaylistId: item.contentDetails?.relatedPlaylists?.uploads,
  };
}

async function fetchAllVideoIds(uploadsPlaylistId) {
  const ids = [];
  let pageToken = undefined;
  let page = 0;
  while (true) {
    page++;
    const url =
      `https://www.googleapis.com/youtube/v3/playlistItems` +
      `?part=snippet&playlistId=${encodeURIComponent(uploadsPlaylistId)}` +
      `&maxResults=50` +
      (pageToken ? `&pageToken=${pageToken}` : "") +
      `&key=${API_KEY}`;
    const data = await ytGet(url);
    const pageIds = data.items
      ?.map((it) => it.snippet?.resourceId?.videoId)
      .filter(Boolean) ?? [];
    ids.push(...pageIds);
    process.stdout.write(`\r  playlistItems: ${page}ページ (${ids.length}件)`);
    pageToken = data.nextPageToken;
    if (!pageToken) break;
  }
  console.log();
  return ids;
}

async function fetchVideoDetails(videoIds) {
  const all = [];
  const chunks = [];
  for (let i = 0; i < videoIds.length; i += 50) chunks.push(videoIds.slice(i, i + 50));
  for (let i = 0; i < chunks.length; i++) {
    process.stdout.write(`\r  videos.list: ${i + 1}/${chunks.length}チャンク`);
    const url =
      `https://www.googleapis.com/youtube/v3/videos` +
      `?part=snippet,liveStreamingDetails,status` +
      `&id=${encodeURIComponent(chunks[i].join(","))}` +
      `&key=${API_KEY}`;
    const data = await ytGet(url);
    all.push(...(data.items ?? []));
  }
  console.log();
  return all;
}

function deriveStatus(v) {
  const d = v.liveStreamingDetails;
  if (d?.actualEndTime) return "ended";
  if (d?.actualStartTime) return "live";
  if (v.snippet?.liveBroadcastContent === "upcoming") return "scheduled";
  return "ended";
}

function toRecord(v, streamerId, channelTitle) {
  const d = v.liveStreamingDetails;
  const startTs = d?.actualStartTime ?? d?.scheduledStartTime;
  const endTs = d?.actualEndTime;
  return {
    streamerId,
    streamerNameSnapshot: channelTitle,
    title: v.snippet?.title ?? "(タイトル不明)",
    startAt: startTs ?? null,
    endAt: endTs ?? null,
    status: deriveStatus(v),
    youtubeVideoId: v.id,
    youtubeWatchUrl: `https://www.youtube.com/watch?v=${v.id}`,
    archiveUrl: `https://www.youtube.com/watch?v=${v.id}`,
    categories: [],
    tags: [],
    source: "import",
    importedAt: new Date().toISOString(),
  };
}

// ---- Firestore書き込み（500件ずつバッチ）----
async function importToFirestore(records) {
  const { FieldValue } = require("firebase-admin").firestore;

  // 既存の youtubeVideoId を取得してスキップ判定
  console.log("  📖 既存データ確認中...");
  const existingSnap = await db.collection("streams")
    .where("source", "==", "import")
    .select("youtubeVideoId")
    .get();
  const existingIds = new Set(
    existingSnap.docs.map((d) => d.data().youtubeVideoId).filter(Boolean)
  );

  const newRecords = records.filter(
    (r) => r.youtubeVideoId && !existingIds.has(r.youtubeVideoId)
  );
  console.log(`  既存: ${existingIds.size}件 / 新規: ${newRecords.length}件 / スキップ: ${records.length - newRecords.length}件`);

  if (newRecords.length === 0) {
    console.log("  ✅ 追加するものなし");
    return 0;
  }

  // 500件ずつバッチ書き込み
  const BATCH_SIZE = 500;
  let written = 0;
  for (let i = 0; i < newRecords.length; i += BATCH_SIZE) {
    const chunk = newRecords.slice(i, i + BATCH_SIZE);
    const batch = db.batch();
    for (const rec of chunk) {
      const ref = db.collection("streams").doc();
      // startAt / endAt を Firestore Timestamp に変換
      const data = {
        ...rec,
        startAt: rec.startAt ? new Date(rec.startAt) : null,
        endAt: rec.endAt ? new Date(rec.endAt) : null,
        importedAt: FieldValue.serverTimestamp(),
      };
      batch.set(ref, data);
    }
    await batch.commit();
    written += chunk.length;
    process.stdout.write(`\r  書き込み: ${written}/${newRecords.length}件`);
  }
  console.log();
  return written;
}

// ---- メイン ----
(async () => {
  const allRecords = [];

  for (const handle of handles) {
    console.log(`\n📡 @${handle} の過去配信を取得中...\n`);

    const { channelId, channelTitle, uploadsPlaylistId } = await resolveChannel(handle);
    console.log(`✅ ${channelTitle} (${channelId})`);

    console.log("📋 動画ID取得中...");
    const allIds = await fetchAllVideoIds(uploadsPlaylistId);
    console.log(`   合計 ${allIds.length} 件`);

    console.log("🎬 動画詳細取得中...");
    const details = await fetchVideoDetails(allIds);

    const liveStreams = details.filter((v) => v.liveStreamingDetails != null);
    console.log(`🎥 ライブ配信: ${liveStreams.length} 件`);

    const streamerId = HANDLE_TO_ID[handle] ?? handle;
    const records = liveStreams
      .map((v) => toRecord(v, streamerId, channelTitle))
      .sort((a, b) => {
        if (!a.startAt) return 1;
        if (!b.startAt) return -1;
        return new Date(b.startAt) - new Date(a.startAt);
      });

    allRecords.push(...records);

    // JSONファイル書き出し（1人ずつ）
    if (!doImport) {
      const file = outFile ?? `${handle}_streams.json`;
      writeFileSync(file, JSON.stringify(records, null, 2), "utf-8");
      console.log(`💾 ${file} に書き出しました (${records.length}件)`);
    }
  }

  // Firestoreインポート
  if (doImport) {
    console.log(`\n📤 Firestoreにインポート中... (合計${allRecords.length}件)\n`);
    const written = await importToFirestore(allRecords);
    console.log(`\n✅ インポート完了！ ${written}件追加`);
  }

  // サマリー
  console.log(`\n📊 取得サマリー:`);
  const counts = allRecords.reduce((acc, r) => {
    acc[r.status] = (acc[r.status] ?? 0) + 1;
    return acc;
  }, {});
  Object.entries(counts).forEach(([k, v]) => console.log(`   ${k}: ${v}件`));
})();
