import { Injectable } from '@nestjs/common';
import { TracksService } from '../tracks/tracks.service';
import {
  Collection,
  CollectionDetail,
  CollectionSummary,
} from './collection.types';
import { CollectionsRepository } from './collections.repository';

@Injectable()
export class CollectionsService {
  constructor(
    private readonly repo: CollectionsRepository,
    private readonly tracks: TracksService,
  ) {}

  list(): CollectionSummary[] {
    return this.repo.findAll().map((c) => this.summary(c));
  }

  get(id: string): CollectionDetail {
    const collection = this.repo.findByIdOrFail(id);
    return {
      ...this.summary(collection),
      items: this.tracks.resolveResponses(collection.trackIds),
    };
  }

  create(name: string, trackIds: string[] = []): CollectionDetail {
    const created = this.repo.create(name.trim(), trackIds);
    return this.get(created.id);
  }

  update(
    id: string,
    data: { name?: string; trackIds?: string[] },
  ): CollectionDetail {
    const patch: Partial<Pick<Collection, 'name' | 'trackIds'>> = {};
    if (data.name !== undefined) patch.name = data.name.trim();
    if (data.trackIds !== undefined) patch.trackIds = data.trackIds;
    this.repo.update(id, patch);
    return this.get(id);
  }

  addTracks(id: string, trackIds: string[]): CollectionDetail {
    const collection = this.repo.findByIdOrFail(id);
    const toAdd = trackIds.filter((t) => !collection.trackIds.includes(t));
    this.repo.update(id, { trackIds: [...collection.trackIds, ...toAdd] });
    return this.get(id);
  }

  removeTrack(id: string, trackId: string): CollectionDetail {
    const collection = this.repo.findByIdOrFail(id);
    this.repo.update(id, {
      trackIds: collection.trackIds.filter((t) => t !== trackId),
    });
    return this.get(id);
  }

  remove(id: string): void {
    this.repo.delete(id);
  }

  private summary(collection: Collection): CollectionSummary {
    return { ...collection, trackCount: collection.trackIds.length };
  }
}
