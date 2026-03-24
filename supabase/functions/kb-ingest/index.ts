import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const OPENROUTER_API_KEY = Deno.env.get("OPENROUTER_API_KEY")!;

const EMBEDDING_MODEL = "openai/text-embedding-3-small";
const OPENROUTER_BASE = "https://openrouter.ai/api/v1";

// Chunking params
const TARGET_CHUNK_SIZE = 400; // ~tokens (approx chars / 4)
const CHUNK_OVERLAP = 60; // ~tokens overlap
const TARGET_CHARS = TARGET_CHUNK_SIZE * 4;
const OVERLAP_CHARS = CHUNK_OVERLAP * 4;

// ─── Supabase helpers ───

async function sbFetch(path: string, init?: RequestInit) {
  return fetch(`${SUPABASE_URL}${path}`, {
    ...init,
    headers: {
      ...(init?.headers || {}),
      apikey: SUPABASE_SERVICE_ROLE_KEY,
      Authorization: `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`,
      "content-type": "application/json",
    },
  });
}

// ─── OpenRouter embedding ───

async function getEmbeddings(texts: string[]): Promise<number[][]> {
  // OpenRouter supports batch embeddings
  const res = await fetch(`${OPENROUTER_BASE}/embeddings`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${OPENROUTER_API_KEY}`,
      "content-type": "application/json",
    },
    body: JSON.stringify({
      model: EMBEDDING_MODEL,
      input: texts,
      dimensions: 1024,
    }),
  });

  if (!res.ok) {
    const errText = await res.text();
    throw new Error(`Embedding failed: ${res.status} ${errText}`);
  }

  const data = await res.json();
  return data.data
    .sort((a: { index: number }, b: { index: number }) => a.index - b.index)
    .map((d: { embedding: number[] }) => d.embedding);
}

// ─── Text chunking ───

function chunkText(text: string): string[] {
  const chunks: string[] = [];
  const paragraphs = text.split(/\n\n+/);
  let currentChunk = "";

  for (const para of paragraphs) {
    if (currentChunk.length + para.length > TARGET_CHARS && currentChunk.length > 0) {
      chunks.push(currentChunk.trim());
      // Overlap: take the last OVERLAP_CHARS of the current chunk
      const overlapStart = Math.max(0, currentChunk.length - OVERLAP_CHARS);
      currentChunk = currentChunk.slice(overlapStart) + "\n\n" + para;
    } else {
      currentChunk += (currentChunk ? "\n\n" : "") + para;
    }
  }

  if (currentChunk.trim()) {
    chunks.push(currentChunk.trim());
  }

  // If any chunk is still too large, split by sentences
  const finalChunks: string[] = [];
  for (const chunk of chunks) {
    if (chunk.length > TARGET_CHARS * 1.5) {
      const sentences = chunk.split(/(?<=[.!?])\s+/);
      let sub = "";
      for (const sent of sentences) {
        if (sub.length + sent.length > TARGET_CHARS && sub.length > 0) {
          finalChunks.push(sub.trim());
          const overlapStart = Math.max(0, sub.length - OVERLAP_CHARS);
          sub = sub.slice(overlapStart) + " " + sent;
        } else {
          sub += (sub ? " " : "") + sent;
        }
      }
      if (sub.trim()) finalChunks.push(sub.trim());
    } else {
      finalChunks.push(chunk);
    }
  }

  return finalChunks;
}

// ─── Main handler ───

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", {
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
      },
    });
  }

  try {
    // Admin-only: check service_role via JWT role claim
    const authHeader = req.headers.get("authorization") ?? "";
    const token = authHeader.replace("Bearer ", "");

    let isAdmin = false;
    try {
      const parts = token.split(".");
      if (parts.length === 3) {
        const payload = JSON.parse(atob(parts[1].replace(/-/g, "+").replace(/_/g, "/")));
        isAdmin = payload.role === "service_role";
      }
    } catch { /* not a valid JWT */ }

    if (!isAdmin) {
      return jsonResponse({ error: "Admin access required" }, 403);
    }

    const body = await req.json();
    const documentId = body.document_id;

    if (!documentId) {
      return jsonResponse({ error: "document_id required" }, 400);
    }

    // 1. Get active version content
    const versionRes = await sbFetch(
      `/rest/v1/kb_document_versions?document_id=eq.${documentId}&is_active=eq.true&select=id,content_markdown,version_no&limit=1`
    );
    const versions = await versionRes.json();
    if (!versions?.length) {
      return jsonResponse({ error: "No active version found for this document" }, 404);
    }
    const version = versions[0];

    // 2. Delete existing chunks for this document+version
    await sbFetch(
      `/rest/v1/kb_chunks?document_id=eq.${documentId}&document_version_id=eq.${version.id}`,
      { method: "DELETE" }
    );

    // 3. Chunk the content
    const chunks = chunkText(version.content_markdown);
    console.log(`Document ${documentId}: ${chunks.length} chunks created`);

    if (chunks.length === 0) {
      return jsonResponse({ message: "No content to index", chunks_count: 0 });
    }

    // 4. Get embeddings in batches (max 20 per request to be safe)
    const BATCH_SIZE = 20;
    const allEmbeddings: number[][] = [];

    for (let i = 0; i < chunks.length; i += BATCH_SIZE) {
      const batch = chunks.slice(i, i + BATCH_SIZE);
      const embeddings = await getEmbeddings(batch);
      allEmbeddings.push(...embeddings);
    }

    // 5. Save chunks with embeddings
    const chunkRecords = chunks.map((chunkText, idx) => ({
      document_id: documentId,
      document_version_id: version.id,
      chunk_no: idx + 1,
      chunk_text: chunkText,
      token_count: Math.ceil(chunkText.length / 4),
      embedding: JSON.stringify(allEmbeddings[idx]),
      metadata: { version_no: version.version_no },
    }));

    // Insert in batches
    for (let i = 0; i < chunkRecords.length; i += 10) {
      const batch = chunkRecords.slice(i, i + 10);
      const insertRes = await sbFetch(`/rest/v1/kb_chunks`, {
        method: "POST",
        body: JSON.stringify(batch),
      });
      if (!insertRes.ok) {
        const errText = await insertRes.text();
        throw new Error(`Failed to insert chunks: ${insertRes.status} ${errText}`);
      }
    }

    return jsonResponse({
      message: "Indexing complete",
      document_id: documentId,
      version_id: version.id,
      chunks_count: chunks.length,
    });
  } catch (err) {
    console.error("KB Ingest error:", err);
    return jsonResponse({ error: String(err) }, 500);
  }
});

function jsonResponse(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      "content-type": "application/json",
      "Access-Control-Allow-Origin": "*",
    },
  });
}
