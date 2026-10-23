import { TrackResponse } from '../tracks/track.types';

/** Playlist/colecao manual criada pelo usuario. */
export interface Collection {
  id: string;
  name: string;
  /** IDs das faixas, na ordem. */
  trackIds: string[];
  createdAt: string;
  updatedAt: string;
}

/** Colecao com contagem (para listagem). */
export interface CollectionSummary extends Collection {
  trackCount: number;
}

/** Colecao com as faixas resolvidas (para a tela da playlist). */
export interface CollectionDetail extends CollectionSummary {
  items: TrackResponse[];
}
