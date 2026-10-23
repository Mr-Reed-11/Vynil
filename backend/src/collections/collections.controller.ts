import {
  Body,
  Controller,
  Delete,
  Get,
  HttpCode,
  HttpStatus,
  Param,
  Patch,
  Post,
} from '@nestjs/common';
import {
  CollectionDetail,
  CollectionSummary,
} from './collection.types';
import { CollectionsService } from './collections.service';
import {
  AddTracksDto,
  CreateCollectionDto,
  UpdateCollectionDto,
} from './dto/collection.dto';

@Controller('collections')
export class CollectionsController {
  constructor(private readonly collections: CollectionsService) {}

  @Get()
  list(): CollectionSummary[] {
    return this.collections.list();
  }

  @Post()
  create(@Body() dto: CreateCollectionDto): CollectionDetail {
    return this.collections.create(dto.name, dto.trackIds ?? []);
  }

  @Get(':id')
  get(@Param('id') id: string): CollectionDetail {
    return this.collections.get(id);
  }

  @Patch(':id')
  update(
    @Param('id') id: string,
    @Body() dto: UpdateCollectionDto,
  ): CollectionDetail {
    return this.collections.update(id, dto);
  }

  @Post(':id/tracks')
  addTracks(
    @Param('id') id: string,
    @Body() dto: AddTracksDto,
  ): CollectionDetail {
    return this.collections.addTracks(id, dto.trackIds);
  }

  @Delete(':id/tracks/:trackId')
  removeTrack(
    @Param('id') id: string,
    @Param('trackId') trackId: string,
  ): CollectionDetail {
    return this.collections.removeTrack(id, trackId);
  }

  @Delete(':id')
  @HttpCode(HttpStatus.NO_CONTENT)
  remove(@Param('id') id: string): void {
    this.collections.remove(id);
  }
}
