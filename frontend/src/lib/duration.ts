const TYPE_DURATIONS: Record<string, number> = {
  museum: 150, art_gallery: 120, park: 90, restaurant: 90,
  cafe: 60, bar: 90, night_club: 120, movie_theater: 150,
  shopping_mall: 120, clothing_store: 60, book_store: 60,
  library: 90, gym: 75, spa: 120, zoo: 180, aquarium: 120,
  amusement_park: 240, bowling_alley: 90, stadium: 180,
  tourist_attraction: 120, church: 60,
};

const KEYWORD_DURATIONS: [RegExp, number][] = [
  [/\b(museum|exhibit|gallery)\b/i, 150],
  [/\b(park|walk|hike|trail|garden)\b/i, 90],
  [/\b(restaurant|dinner|lunch|brunch|eat)\b/i, 90],
  [/\b(coffee|cafe|tea)\b/i, 60],
  [/\b(bar|drinks|cocktail|happy hour)\b/i, 90],
  [/\b(movie|film|cinema|theater)\b/i, 150],
  [/\b(shop|mall|store|market)\b/i, 120],
  [/\b(gym|workout|yoga|pilates|climb)\b/i, 75],
  [/\b(spa|massage)\b/i, 120],
  [/\b(zoo|aquarium)\b/i, 150],
  [/\b(concert|show|performance|play)\b/i, 150],
  [/\b(beach|swim|pool)\b/i, 120],
  [/\b(run|jog)\b/i, 45],
];

export function estimateDuration(title: string, placeTypes: string[] = []): number {
  for (const type of placeTypes) {
    if (TYPE_DURATIONS[type]) return TYPE_DURATIONS[type];
  }
  for (const [pattern, minutes] of KEYWORD_DURATIONS) {
    if (pattern.test(title)) return minutes;
  }
  return 60;
}

export function formatDuration(minutes: number): string {
  if (minutes < 60) return `${minutes} min`;
  const h = Math.floor(minutes / 60);
  const m = minutes % 60;
  if (m === 0) return h === 1 ? "1 hour" : `${h} hours`;
  return `${h}.${Math.round((m / 60) * 10)} hours`;
}
