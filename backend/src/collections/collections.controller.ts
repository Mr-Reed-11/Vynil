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
import { AuthUser, CurrentUser } from '../auth/current-user.decorator';
import { CollectionDetail, CollectionSummary } from './collection.types';
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
  list(@CurrentUser() user: AuthUser): CollectionSummary[] {
    return this.collections.list(user.userId);
  }

  @Post()
  create(
    @CurrentUser() user: AuthUser,
    @Body() dto: CreateCollectionDto,
  ): CollectionDetail {
    return this.collections.create(user.userId, dto.name, dto.trackIds ?? []);
  }

  @Get(':id')
  get(
    @CurrentUser() user: AuthUser,
    @Param('id') id: string,
  ): CollectionDetail {
    return this.collections.get(user.userId, id);
  }

  @Patch(':id')
  update(
    @CurrentUser() user: AuthUser,
    @Param('id') id: string,
    @Body() dto: UpdateCollectionDto,
  ): CollectionDetail {
    return this.collections.update(user.userId, id, dto);
  }

  @Post(':id/tracks')
  addTracks(
    @CurrentUser() user: AuthUser,
    @Param('id') id: string,
    @Body() dto: AddTracksDto,
  ): CollectionDetail {
    return this.collections.addTracks(user.userId, id, dto.trackIds);
  }

  @Delete(':id/tracks/:trackId')
  removeTrack(
    @CurrentUser() user: AuthUser,
    @Param('id') id: string,
    @Param('trackId') trackId: string,
  ): CollectionDetail {
    return this.collections.removeTrack(user.userId, id, trackId);
  }

  @Delete(':id')
  @HttpCode(HttpStatus.NO_CONTENT)
  remove(@CurrentUser() user: AuthUser, @Param('id') id: string): void {
    this.collections.remove(user.userId, id);
  }
}
