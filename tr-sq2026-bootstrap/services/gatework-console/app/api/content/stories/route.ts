import { NextResponse } from 'next/server';
import { listOfficialStories, publishOfficialStory } from '@/lib/content';

const noStore = { 'cache-control': 'no-store' };

const failure = (code: string, error: unknown, fallback: string) =>
  NextResponse.json(
    // Servisin kendi cümlesi korunuyor: "Story yayınlanamadı" tek başına
    // editöre görselin taranmasını mı beklemesi, yoksa hesabın kapalı mı
    // olduğunu anlatmıyor.
    { error: { code, message: error instanceof Error ? error.message : fallback } },
    { status: 400, headers: noStore },
  );

export async function GET() {
  try {
    return NextResponse.json({ data: await listOfficialStories() }, { headers: noStore });
  } catch (error) {
    return failure('STORIES_UNAVAILABLE', error, 'Yayındaki Storyler okunamadı.');
  }
}

export async function POST(request: Request) {
  try {
    return NextResponse.json({ data: await publishOfficialStory(await request.json()) }, { status: 201, headers: noStore });
  } catch (error) {
    return failure('STORY_REJECTED', error, 'Story yayınlanamadı.');
  }
}
