import { Home, Map, List, Plus } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { cn } from '@/lib/utils';

type ViewType = 'home' | 'map' | 'list';

interface NavigationProps {
  currentView: ViewType;
  onViewChange: (view: ViewType) => void;
  onAddClick: () => void;
}

export function Navigation({ currentView, onViewChange, onAddClick }: NavigationProps) {
  const navItems: { id: ViewType; label: string; icon: typeof Home }[] = [
    { id: 'home', label: 'Memories', icon: Home },
    { id: 'map', label: 'Map', icon: Map },
    { id: 'list', label: 'All Ideas', icon: List },
  ];

  return (
    <nav className="fixed bottom-0 left-0 right-0 z-50 bg-card/95 backdrop-blur-lg border-t border-border/50 safe-area-pb">
      <div className="max-w-lg mx-auto px-4 py-2">
        <div className="flex items-center justify-around">
          {navItems.map(item => (
            <button
              key={item.id}
              onClick={() => onViewChange(item.id)}
              className={cn(
                "flex flex-col items-center gap-1 px-4 py-2 rounded-xl transition-all duration-200",
                currentView === item.id
                  ? "text-primary bg-primary/10"
                  : "text-muted-foreground hover:text-foreground hover:bg-muted/50"
              )}
            >
              <item.icon className="w-5 h-5" />
              <span className="text-xs font-medium">{item.label}</span>
            </button>
          ))}
          
          <Button
            onClick={onAddClick}
            size="icon"
            className="rounded-full shadow-glow w-12 h-12 -mt-4"
          >
            <Plus className="w-6 h-6" />
          </Button>
        </div>
      </div>
    </nav>
  );
}
