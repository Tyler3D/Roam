import { DatePin } from '@/types/datePin';
import { MemoriesCarousel } from './MemoriesCarousel';
import { DatePinCard } from './DatePinCard';
import { Sparkles, RefreshCw, TrendingUp } from 'lucide-react';

interface HomeViewProps {
  recentPins: DatePin[];
  forgottenPins: DatePin[];
  allPins: DatePin[];
  onPinClick: (pin: DatePin) => void;
}

export function HomeView({ recentPins, forgottenPins, allPins, onPinClick }: HomeViewProps) {
  // Get a random "pick for you" pin
  const savedPins = allPins.filter(p => p.status === 'saved');
  const pickForYou = savedPins.length > 0 
    ? savedPins[Math.floor(Math.random() * savedPins.length)]
    : null;

  // Get planned dates
  const plannedPins = allPins.filter(p => p.status === 'planned');

  return (
    <div className="space-y-8 pb-8">
      {/* Hero Section */}
      <section className="text-center py-6 animate-fade-in">
        <div className="inline-flex items-center gap-2 bg-primary/10 text-primary px-4 py-2 rounded-full mb-4">
          <Sparkles className="w-4 h-4" />
          <span className="text-sm font-medium">Your Date Ideas</span>
        </div>
        <h2 className="font-display text-3xl font-bold text-foreground mb-2">
          What should we do?
        </h2>
        <p className="text-muted-foreground max-w-md mx-auto">
          {allPins.length} ideas saved for your adventures together
        </p>
      </section>

      {/* Pick for You */}
      {pickForYou && (
        <section className="animate-fade-in" style={{ animationDelay: '100ms' }}>
          <div className="flex items-center gap-2 mb-4">
            <TrendingUp className="w-5 h-5 text-highlight" />
            <h2 className="font-display text-xl font-semibold text-foreground">
              Tonight's Pick
            </h2>
          </div>
          <div className="glow-card rounded-2xl p-6 memory-gradient">
            <DatePinCard 
              pin={pickForYou} 
              onClick={() => onPinClick(pickForYou)} 
            />
          </div>
        </section>
      )}

      {/* Recently Added */}
      {recentPins.length > 0 && (
        <MemoriesCarousel
          title="Recently Added"
          subtitle="Fresh ideas from this week"
          pins={recentPins}
          icon="sparkles"
          onPinClick={onPinClick}
        />
      )}

      {/* Planned Dates */}
      {plannedPins.length > 0 && (
        <section className="animate-fade-in" style={{ animationDelay: '200ms' }}>
          <div className="flex items-center gap-2 mb-4">
            <div className="w-5 h-5 rounded-full bg-highlight/20 flex items-center justify-center">
              <span className="text-highlight text-xs font-bold">{plannedPins.length}</span>
            </div>
            <h2 className="font-display text-xl font-semibold text-foreground">
              Planned
            </h2>
          </div>
          <div className="space-y-3">
            {plannedPins.slice(0, 3).map(pin => (
              <DatePinCard 
                key={pin.id} 
                pin={pin} 
                variant="compact" 
                onClick={() => onPinClick(pin)} 
              />
            ))}
          </div>
        </section>
      )}

      {/* Rediscover */}
      {forgottenPins.length > 0 && (
        <MemoriesCarousel
          title="Rediscover"
          subtitle="Ideas you might have forgotten"
          pins={forgottenPins}
          icon="clock"
          onPinClick={onPinClick}
        />
      )}

      {/* Empty State */}
      {allPins.length === 0 && (
        <div className="text-center py-12">
          <RefreshCw className="w-12 h-12 text-muted-foreground/30 mx-auto mb-4" />
          <h3 className="font-display text-xl font-semibold text-foreground mb-2">
            No ideas yet
          </h3>
          <p className="text-muted-foreground max-w-sm mx-auto">
            Start saving date ideas from TikToks, conversations, or random inspiration. 
            They'll all live here waiting for when you need them.
          </p>
        </div>
      )}
    </div>
  );
}
