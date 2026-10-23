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

  list(userId: string): CollectionSummary[] {
    return this.repo.findAll(userId).map((c) => this.summary(c));
  }

  get(userId: string, id: string): CollectionDetail {
    const collection = this.repo.findByIdOrFail(userId, id);
    return {
      ...this.summary(collection),
      items: this.tracks.resolveResponses(userId, collection.trackIds),
    };
  }

  create(userId: string, name: string, trackIds: string[] = []): CollectionDetail {
    const created = this.repo.create(userId, name.trim(), trackIds);
    return this.get(userId, created.id);
  }

  update(
    userId: string,
    id: string,
    data: { name?: string; trackIds?: string[] },
  ): CollectionDetail {
    const patch: Partial<Pick<Collection, 'name' | 'trackIds'>> = {};
    if (data.name !== undefined) patch.name = data.name.trim();
    if (data.trackIds !== undefined) patch.trackIds = data.trackIds;
    this.repo.update(userId, id, patch);
    return this.get(userId, id);
  }

  addTracks(userId: string, id: string, trackIds: string[]): CollectionDetail {
    const collection = this.repo.findByIdOrFail(userId, id);
    const toAdd = trackIds.filter((t) => !collection.trackIds.includes(t));
    this.repo.update(userId, id, {
      trackIds: [...collection.trackIds, ...toAdd],
    });
    return this.get(userId, id);
  }

  removeTrack(userId: string, id: string, trackId: string): CollectionDetail {
    const collection = this.repo.findByIdOrFail(userId, id);
    this.repo.update(userId, id, {
      trackIds: collection.trackIds.filter((t) => t !== trackId),
    });
    return this.get(userId, id);
  }

  remove(userId: string, id: string): void {
    this.repo.delete(userId, id);
  }

  private summary(collection: Collection): CollectionSummary {
    return { ...collection, trackCount: collection.trackIds.length };
  }
}
