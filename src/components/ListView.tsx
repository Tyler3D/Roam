import { useState, useMemo } from 'react';
import { DatePin, DatePinType, DatePinStatus } from '@/types/datePin';
import { DatePinCard } from './DatePinCard';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Search, Filter, SortDesc } from 'lucide-react';
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu';
import { cn } from '@/lib/utils';

interface ListViewProps {
  pins: DatePin[];
  onPinClick: (pin: DatePin) => void;
}

type SortOption = 'recent' | 'oldest' | 'alphabetical';
type FilterType = 'all' | DatePinType;
type FilterStatus = 'all' | DatePinStatus;

export function ListView({ pins, onPinClick }: ListViewProps) {
  const [search, setSearch] = useState('');
  const [sortBy, setSortBy] = useState<SortOption>('recent');
  const [filterType, setFilterType] = useState<FilterType>('all');
  const [filterStatus, setFilterStatus] = useState<FilterStatus>('all');

  const filteredAndSortedPins = useMemo(() => {
    let result = [...pins];

    // Filter by search
    if (search) {
      const searchLower = search.toLowerCase();
      result = result.filter(pin =>
        pin.title.toLowerCase().includes(searchLower) ||
        pin.notes?.toLowerCase().includes(searchLower) ||
        pin.location?.name.toLowerCase().includes(searchLower) ||
        pin.tags?.some(tag => tag.toLowerCase().includes(searchLower))
      );
    }

    // Filter by type
    if (filterType !== 'all') {
      result = result.filter(pin => pin.type === filterType);
    }

    // Filter by status
    if (filterStatus !== 'all') {
      result = result.filter(pin => pin.status === filterStatus);
    }

    // Sort
    switch (sortBy) {
      case 'recent':
        result.sort((a, b) => b.createdAt.getTime() - a.createdAt.getTime());
        break;
      case 'oldest':
        result.sort((a, b) => a.createdAt.getTime() - b.createdAt.getTime());
        break;
      case 'alphabetical':
        result.sort((a, b) => a.title.localeCompare(b.title));
        break;
    }

    return result;
  }, [pins, search, sortBy, filterType, filterStatus]);

  const typeOptions: { value: FilterType; label: string }[] = [
    { value: 'all', label: 'All Types' },
    { value: 'restaurant', label: 'Restaurant' },
    { value: 'outdoor', label: 'Outdoor' },
    { value: 'home', label: 'At Home' },
    { value: 'event', label: 'Event' },
  ];

  const statusOptions: { value: FilterStatus; label: string }[] = [
    { value: 'all', label: 'All Status' },
    { value: 'saved', label: 'Saved' },
    { value: 'planned', label: 'Planned' },
    { value: 'done', label: 'Done' },
  ];

  return (
    <div className="space-y-6">
      {/* Search and Filters */}
      <div className="flex flex-col sm:flex-row gap-3">
        <div className="relative flex-1">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-muted-foreground" />
          <Input
            placeholder="Search ideas..."
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            className="pl-9 bg-card"
          />
        </div>

        <div className="flex gap-2">
          <DropdownMenu>
            <DropdownMenuTrigger asChild>
              <Button variant="outline" size="icon" className="bg-card">
                <Filter className="w-4 h-4" />
              </Button>
            </DropdownMenuTrigger>
            <DropdownMenuContent align="end" className="w-48">
              <DropdownMenuLabel>Type</DropdownMenuLabel>
              {typeOptions.map(option => (
                <DropdownMenuItem
                  key={option.value}
                  onClick={() => setFilterType(option.value)}
                  className={cn(filterType === option.value && "bg-muted")}
                >
                  {option.label}
                </DropdownMenuItem>
              ))}
              <DropdownMenuSeparator />
              <DropdownMenuLabel>Status</DropdownMenuLabel>
              {statusOptions.map(option => (
                <DropdownMenuItem
                  key={option.value}
                  onClick={() => setFilterStatus(option.value)}
                  className={cn(filterStatus === option.value && "bg-muted")}
                >
                  {option.label}
                </DropdownMenuItem>
              ))}
            </DropdownMenuContent>
          </DropdownMenu>

          <DropdownMenu>
            <DropdownMenuTrigger asChild>
              <Button variant="outline" size="icon" className="bg-card">
                <SortDesc className="w-4 h-4" />
              </Button>
            </DropdownMenuTrigger>
            <DropdownMenuContent align="end">
              <DropdownMenuItem 
                onClick={() => setSortBy('recent')}
                className={cn(sortBy === 'recent' && "bg-muted")}
              >
                Most Recent
              </DropdownMenuItem>
              <DropdownMenuItem 
                onClick={() => setSortBy('oldest')}
                className={cn(sortBy === 'oldest' && "bg-muted")}
              >
                Oldest First
              </DropdownMenuItem>
              <DropdownMenuItem 
                onClick={() => setSortBy('alphabetical')}
                className={cn(sortBy === 'alphabetical' && "bg-muted")}
              >
                Alphabetical
              </DropdownMenuItem>
            </DropdownMenuContent>
          </DropdownMenu>
        </div>
      </div>

      {/* Active Filters */}
      {(filterType !== 'all' || filterStatus !== 'all') && (
        <div className="flex items-center gap-2 flex-wrap">
          <span className="text-sm text-muted-foreground">Filters:</span>
          {filterType !== 'all' && (
            <Button
              variant="secondary"
              size="sm"
              onClick={() => setFilterType('all')}
              className="h-7 text-xs"
            >
              {typeOptions.find(o => o.value === filterType)?.label} ×
            </Button>
          )}
          {filterStatus !== 'all' && (
            <Button
              variant="secondary"
              size="sm"
              onClick={() => setFilterStatus('all')}
              className="h-7 text-xs"
            >
              {statusOptions.find(o => o.value === filterStatus)?.label} ×
            </Button>
          )}
        </div>
      )}

      {/* Results Count */}
      <p className="text-sm text-muted-foreground">
        {filteredAndSortedPins.length} date idea{filteredAndSortedPins.length !== 1 ? 's' : ''}
      </p>

      {/* Pin Grid */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
        {filteredAndSortedPins.map((pin, index) => (
          <div 
            key={pin.id}
            style={{ animationDelay: `${index * 50}ms` }}
          >
            <DatePinCard pin={pin} onClick={() => onPinClick(pin)} />
          </div>
        ))}
      </div>

      {/* Empty State */}
      {filteredAndSortedPins.length === 0 && (
        <div className="text-center py-12">
          <p className="text-muted-foreground">No date ideas match your filters</p>
          <Button
            variant="link"
            onClick={() => {
              setSearch('');
              setFilterType('all');
              setFilterStatus('all');
            }}
            className="mt-2"
          >
            Clear all filters
          </Button>
        </div>
      )}
    </div>
  );
}
