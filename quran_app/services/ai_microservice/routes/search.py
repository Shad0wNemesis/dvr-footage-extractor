"""
/api/search  — Semantic RAG search over the Quran corpus.

Pipeline
--------
1. Embed the user's natural-language query (EmbeddingService)
2. Retrieve top-K candidate Ayahs from the FAISS index (VectorStore)
3. (Optional) Build a grounded LLM answer using retrieved Ayahs + Tafseer (LLMService)
4. Return ranked Ayah list + optional answer to the Flutter app
"""

from __future__ import annotations

import time

from fastapi import APIRouter, HTTPException, Request

from models.schemas import (
    AyahResult,
    SemanticSearchRequest,
    SemanticSearchResponse,
)

router = APIRouter()


@router.post("", response_model=SemanticSearchResponse)
async def semantic_search(
    request: Request,
    body: SemanticSearchRequest,
) -> SemanticSearchResponse:
    """
    Natural-language semantic search over all 6,236 Ayahs and their Tafseers.

    Example request:
        { "query": "verses about patience during hardship", "top_k": 5 }
    """
    total_start = time.perf_counter()

    vector_store = request.app.state.vector_store
    llm_service = request.app.state.llm

    if not vector_store.is_loaded:
        raise HTTPException(
            status_code=503,
            detail="Vector store not yet initialised. Retry in a moment.",
        )

    # ── Retrieval ─────────────────────────────────────────────────────────
    raw_results, embedding_ms, retrieval_ms = await vector_store.search(
        query=body.query,
        top_k=min(body.top_k * 3, 20),  # Over-fetch for re-ranking
    )

    if not raw_results:
        return SemanticSearchResponse(
            results=[],
            answer=None,
            query_embedding_ms=embedding_ms,
            retrieval_ms=retrieval_ms,
            total_ms=(time.perf_counter() - total_start) * 1000,
        )

    # ── Build AyahResult objects ──────────────────────────────────────────
    ayah_results = [
        AyahResult(
            verse_key=r["verse_key"],
            surah_id=r["surah_id"],
            ayah_number=r["ayah_number"],
            surah_name=r.get("surah_name", ""),
            text_arabic=r.get("text_arabic", ""),
            translation_en=r.get("translation_en"),
            tafseer_snippet=r.get("tafseer_snippet") if body.include_tafseer else None,
            relevance_score=r["relevance_score"],
        )
        for r in raw_results
    ]

    # Trim to requested top_k after we've built the full list.
    ayah_results = sorted(ayah_results, key=lambda x: x.relevance_score, reverse=True)
    ayah_results = ayah_results[:body.top_k]

    # ── LLM grounded answer ────────────────────────────────────────────────
    llm_ms: float | None = None
    answer: str | None = None

    if llm_service.is_loaded:
        t_llm = time.perf_counter()
        context_blocks = []
        for r in ayah_results:
            block = f"[{r.verse_key}] {r.text_arabic}"
            if r.translation_en:
                block += f"\nTranslation: {r.translation_en}"
            if r.tafseer_snippet:
                block += f"\nTafseer: {r.tafseer_snippet}"
            context_blocks.append(block)

        prompt = _build_rag_prompt(body.query, context_blocks)
        answer = await llm_service.generate(prompt)
        llm_ms = (time.perf_counter() - t_llm) * 1000

    total_ms = (time.perf_counter() - total_start) * 1000

    return SemanticSearchResponse(
        results=ayah_results,
        answer=answer,
        query_embedding_ms=embedding_ms,
        retrieval_ms=retrieval_ms,
        llm_ms=llm_ms,
        total_ms=total_ms,
    )


def _build_rag_prompt(query: str, context_blocks: list[str]) -> str:
    """
    Constructs a RAG prompt for the local LLM.

    We use a strict instruction format to keep the model grounded in the
    retrieved Ayahs and prevent hallucination about Quranic content.
    """
    context = "\n\n".join(context_blocks)
    return f"""You are a knowledgeable Islamic scholar assistant.
Answer the user's question using ONLY the Quranic verses provided below.
Do not add information that is not present in the context.
If the context does not fully answer the question, say so clearly.

USER QUESTION: {query}

RELEVANT QURANIC VERSES:
{context}

ANSWER (concise, cite verse keys in brackets like [2:255]):"""
