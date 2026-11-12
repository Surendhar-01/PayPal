"""Demand embeddings are disabled without Ollama.

Ollama has been removed from the platform. Demand embedding generation,
persistence, and semantic search are disabled. Callers should handle
the configuration error gracefully and fall back to exact taxonomy
matching instead of semantic embedding search.
"""

import logging
from dataclasses import dataclass
from typing import Any, Literal, Mapping, Optional, Sequence

from app.core.config import Settings, get_settings
from app.services.ai.base import AIProviderConfigurationError

logger = logging.getLogger("markettwin.demand_embeddings")


@dataclass(frozen=True)
class DemandEmbeddingResult:
    embedding: list[float]
    embedding_model: str
    embedding_version: str
    input_hash: str


@dataclass(frozen=True)
class DemandEmbeddingCandidate:
    demand_id: str
    cosine_distance: float
    cosine_similarity: float


@dataclass(frozen=True)
class StoredDemandEmbedding:
    embedding: list[float]
    embedding_model: str
    embedding_version: str
    input_hash: str


class DemandEmbeddingService:
    """Demand embeddings are not available without Ollama.

    Ollama has been removed from the platform. Demand embedding generation,
    persistence, and semantic search are disabled. Callers should handle
    the configuration error gracefully.
    """

    def __init__(
        self,
        settings: Optional[Settings] = None,
        transport: Optional[Any] = None,
    ) -> None:
        self._settings = settings or get_settings()
        self._transport = transport
        raise AIProviderConfigurationError(
            "Demand embeddings require Ollama, which has been removed from the platform. "
            "Use exact taxonomy matching instead of semantic embedding search."
        )

    async def generate(self, demand: Mapping[str, Any]) -> DemandEmbeddingResult:
        raise AIProviderConfigurationError(
            "Demand embedding generation is disabled; Ollama has been removed."
        )


def get_demand_embedding(
    demand_id: str,
    client: Optional[Any] = None,
) -> Optional[StoredDemandEmbedding]:
    """Read and validate a stored vector using the service-role client only.

    Embeddings are disabled because Ollama has been removed. This function
    always returns None.
    """
    return None


def persist_demand_embedding(
    demand_id: str,
    result: DemandEmbeddingResult,
    client: Optional[Any] = None,
) -> Literal["saved", "unchanged"]:
    """Persist an embedding through the configured backend Supabase client.

    Embeddings are disabled because Ollama has been removed.
    """
    raise AIProviderConfigurationError(
        "Demand embedding persistence is disabled; Ollama has been removed."
    )


def search_demand_embedding_candidates(
    query_embedding: Sequence[float],
    embedding_model: str,
    embedding_version: str,
    exclude_demand_id: Optional[str] = None,
    candidate_limit: int = 20,
    max_cosine_distance: float = 0.4,
    client: Optional[Any] = None,
) -> list[DemandEmbeddingCandidate]:
    """Search compatible demand embeddings through the read-only pgvector RPC.

    Embeddings are disabled because Ollama has been removed.
    """
    raise AIProviderConfigurationError(
        "Demand embedding search is disabled; Ollama has been removed."
    )
