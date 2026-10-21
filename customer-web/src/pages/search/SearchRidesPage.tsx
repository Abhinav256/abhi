import React, { useState, useEffect } from 'react';
import {
  Search,
  ArrowUpDown,
  Filter,
  Car,
} from 'lucide-react';
import { api } from '../../services/api';
import type { Ride } from '../../types';
import { RideCard } from '../../components/rides/RideCard';

export const SearchRidesPage: React.FC = () => {
  const [fromLocation, setFromLocation] = useState('');
  const [toLocation, setToLocation] = useState('');
  const [journeyDate, setJourneyDate] = useState(() => {
    return new Date().toISOString().split('T')[0];
  });

  const [rides, setRides] = useState<Ride[]>([]);
  const [loading, setLoading] = useState(false);

  // Filters & Sorting
  const [selectedSort, setSelectedSort] = useState<'default' | 'cheapest' | 'fastest'>('default');
  const [femaleOnly, setFemaleOnly] = useState(false);
  const [capacityFilters, setCapacityFilters] = useState<Set<number>>(new Set());

  // Quick Date select helpers
  const todayStr = new Date().toISOString().split('T')[0];
  const tomorrowStr = (() => {
    const d = new Date();
    d.setDate(d.getDate() + 1);
    return d.toISOString().split('T')[0];
  })();

  const handleSwap = () => {
    const temp = fromLocation;
    setFromLocation(toLocation);
    setToLocation(temp);
  };

  const handleSearch = async (e?: React.FormEvent) => {
    if (e) e.preventDefault();
    setLoading(true);

    try {
      const results = await api.searchRides({
        fromLocation: fromLocation.trim() || undefined,
        toLocation: toLocation.trim() || undefined,
        journeyDate: journeyDate || undefined,
      });
      setRides(results);
    } catch (err) {
      console.error('Failed to search rides:', err);
      setRides([]);
    } finally {
      setLoading(false);
    }
  };

  // Perform initial search on load
  useEffect(() => {
    handleSearch();
  }, []);

  // Filter capacity toggle
  const toggleCapacity = (seats: number) => {
    setCapacityFilters((prev) => {
      const next = new Set(prev);
      if (next.has(seats)) {
        next.delete(seats);
      } else {
        next.add(seats);
      }
      return next;
    });
  };

  const resetFilters = () => {
    setSelectedSort('default');
    setFemaleOnly(false);
    setCapacityFilters(new Set());
  };

  // Helper to extract vehicle seats matching Flutter's _vehicleSeats logic
  const getVehicleSeats = (ride: any): number | null => {
    const rawType = (
      ride.vehicle_type ||
      ride.vehicle?.vehicle_type ||
      ride.type ||
      ''
    ).toLowerCase();

    if (rawType) {
      if (rawType === 'two_wheeler' || rawType.includes('2') || rawType.includes('two')) return 2;
      if (rawType === 'five_seater' || rawType.includes('5') || rawType.includes('five')) return 5;
      if (rawType === 'seven_seater' || rawType.includes('7') || rawType.includes('seven')) return 7;
    }

    const rawSeats =
      ride.vehicle_seats ??
      ride.vehicle_capacity ??
      ride.total_seats ??
      ride.seater ??
      ride.seats ??
      ride.vehicle?.total_seats;

    if (rawSeats != null) {
      const parsed = parseInt(String(rawSeats), 10);
      if (!isNaN(parsed)) return parsed;
    }
    return null;
  };

  // Filter and sort the search results
  const filteredRides = rides.filter((ride) => {
    if (femaleOnly) {
      const isFemale =
        ride.female_only ||
        ride.driver?.gender === 'female' ||
        (ride as any).driver_gender === 'female';
      if (!isFemale) return false;
    }

    if (capacityFilters.size > 0) {
      const seats = getVehicleSeats(ride);
      if (!seats || !capacityFilters.has(seats)) {
        return false;
      }
    }

    return true;
  });

  const sortedRides = [...filteredRides].sort((a, b) => {
    if (selectedSort === 'cheapest') {
      return (a.price_per_seat || 0) - (b.price_per_seat || 0);
    }
    if (selectedSort === 'fastest') {
      const durA = (a.estimated_arrival_time || '99') > (a.departure_time || '00');
      const durB = (b.estimated_arrival_time || '99') > (b.departure_time || '00');
      return durA === durB ? 0 : durA ? -1 : 1;
    }
    return (a.departure_time || '').localeCompare(b.departure_time || '');
  });

  return (
    <div className="animate-fade-in" style={{ padding: '1.5rem 0' }}>
      <div className="app-container">
        {/* Page Header */}
        <div style={{ marginBottom: '1.5rem' }}>
          <h1 style={{ fontSize: '1.75rem', fontWeight: 800, color: 'var(--navy)', marginBottom: '0.25rem' }}>
            Search Available Rides
          </h1>
          <p style={{ color: 'var(--grey)', fontSize: '0.95rem' }}>
            Find community carpools traveling along your route.
          </p>
        </div>

        {/* Search Bar Form */}
        <div
          className="card"
          style={{
            padding: '1.5rem',
            background: '#ffffff',
            border: '1.5px solid var(--grey-border)',
            boxShadow: 'var(--shadow-md)',
            marginBottom: '1.5rem',
          }}
        >
          <form
            onSubmit={handleSearch}
            style={{
              display: 'grid',
              gridTemplateColumns: 'repeat(auto-fit, minmax(220px, 1fr)) auto',
              gap: '1rem',
              alignItems: 'flex-end',
            }}
          >
            {/* Origin */}
            <div className="form-group" style={{ margin: 0 }}>
              <label className="form-label">Leaving From</label>
              <input
                type="text"
                placeholder="e.g. Hitec City, Gachibowli"
                value={fromLocation}
                onChange={(e) => setFromLocation(e.target.value)}
                className="input-field"
              />
            </div>

            {/* Swap Button (desktop) */}
            <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
              <button
                type="button"
                onClick={handleSwap}
                style={{
                  width: 42,
                  height: 42,
                  borderRadius: '50%',
                  border: '1.5px solid var(--grey-border)',
                  background: 'var(--bg-header)',
                  color: 'var(--blue)',
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  cursor: 'pointer',
                  transition: 'transform 0.2s',
                }}
                title="Swap locations"
              >
                <ArrowUpDown size={18} />
              </button>
            </div>

            {/* Destination */}
            <div className="form-group" style={{ margin: 0 }}>
              <label className="form-label">Going To</label>
              <input
                type="text"
                placeholder="e.g. Secunderabad, Airport"
                value={toLocation}
                onChange={(e) => setToLocation(e.target.value)}
                className="input-field"
              />
            </div>

            {/* Date Input */}
            <div className="form-group" style={{ margin: 0 }}>
              <label className="form-label">Date of Journey</label>
              <input
                type="date"
                value={journeyDate}
                onChange={(e) => setJourneyDate(e.target.value)}
                className="input-field"
              />
            </div>

            {/* Search Button */}
            <div>
              <button
                type="submit"
                className="btn btn-primary"
                style={{ height: 46, width: '100%', whiteSpace: 'nowrap' }}
                disabled={loading}
              >
                <Search size={18} />
                {loading ? 'Searching...' : 'Find Rides'}
              </button>
            </div>
          </form>

          {/* Quick Date Shortcuts */}
          <div style={{ display: 'flex', gap: '0.5rem', marginTop: '1rem', alignItems: 'center' }}>
            <span style={{ fontSize: '0.8rem', color: 'var(--grey)', fontWeight: 600 }}>Quick date:</span>
            <button
              type="button"
              onClick={() => setJourneyDate(todayStr)}
              className={`badge ${journeyDate === todayStr ? 'badge-blue' : 'badge-grey'}`}
              style={{ cursor: 'pointer', padding: '0.3rem 0.75rem' }}
            >
              Today
            </button>
            <button
              type="button"
              onClick={() => setJourneyDate(tomorrowStr)}
              className={`badge ${journeyDate === tomorrowStr ? 'badge-blue' : 'badge-grey'}`}
              style={{ cursor: 'pointer', padding: '0.3rem 0.75rem' }}
            >
              Tomorrow
            </button>
          </div>
        </div>

        {/* Filter Chips Bar (Working 2-seater, 5-seater, 7-seater filters!) */}
        <div
          style={{
            display: 'flex',
            alignItems: 'center',
            gap: '0.5rem',
            flexWrap: 'wrap',
            marginBottom: '1.5rem',
            background: '#ffffff',
            padding: '0.75rem 1rem',
            borderRadius: 'var(--radius-lg)',
            border: '1px solid var(--grey-border)',
          }}
        >
          <div style={{ display: 'flex', alignItems: 'center', gap: '0.35rem', color: 'var(--navy)', fontWeight: 600, fontSize: '0.85rem', marginRight: '0.5rem' }}>
            <Filter size={16} />
            <span>Filters:</span>
          </div>

          {/* All (Reset) */}
          <button
            type="button"
            onClick={resetFilters}
            className={`btn ${
              selectedSort === 'default' && !femaleOnly && capacityFilters.size === 0
                ? 'btn-secondary'
                : 'btn-outline'
            }`}
            style={{ padding: '0.35rem 0.85rem', fontSize: '0.8rem', borderRadius: 'var(--radius-full)' }}
          >
            All
          </button>

          {/* Cheapest Sort */}
          <button
            type="button"
            onClick={() => setSelectedSort(selectedSort === 'cheapest' ? 'default' : 'cheapest')}
            className={`btn ${selectedSort === 'cheapest' ? 'btn-secondary' : 'btn-outline'}`}
            style={{ padding: '0.35rem 0.85rem', fontSize: '0.8rem', borderRadius: 'var(--radius-full)' }}
          >
            Cheapest
          </button>

          {/* Fastest Sort */}
          <button
            type="button"
            onClick={() => setSelectedSort(selectedSort === 'fastest' ? 'default' : 'fastest')}
            className={`btn ${selectedSort === 'fastest' ? 'btn-secondary' : 'btn-outline'}`}
            style={{ padding: '0.35rem 0.85rem', fontSize: '0.8rem', borderRadius: 'var(--radius-full)' }}
          >
            Fastest
          </button>

          {/* Female Only */}
          <button
            type="button"
            onClick={() => setFemaleOnly(!femaleOnly)}
            className={`btn ${femaleOnly ? 'btn-secondary' : 'btn-outline'}`}
            style={{ padding: '0.35rem 0.85rem', fontSize: '0.8rem', borderRadius: 'var(--radius-full)' }}
          >
            Female Only
          </button>

          <div style={{ width: 1, height: 20, background: 'var(--grey-border)', margin: '0 0.25rem' }} />

          {/* 2 Seater Filter */}
          <button
            type="button"
            onClick={() => toggleCapacity(2)}
            className={`btn ${capacityFilters.has(2) ? 'btn-primary' : 'btn-outline'}`}
            style={{ padding: '0.35rem 0.85rem', fontSize: '0.8rem', borderRadius: 'var(--radius-full)' }}
          >
            <Car size={13} />
            2 Seater
          </button>

          {/* 5 Seater Filter */}
          <button
            type="button"
            onClick={() => toggleCapacity(5)}
            className={`btn ${capacityFilters.has(5) ? 'btn-primary' : 'btn-outline'}`}
            style={{ padding: '0.35rem 0.85rem', fontSize: '0.8rem', borderRadius: 'var(--radius-full)' }}
          >
            <Car size={13} />
            5 Seater
          </button>

          {/* 7 Seater Filter */}
          <button
            type="button"
            onClick={() => toggleCapacity(7)}
            className={`btn ${capacityFilters.has(7) ? 'btn-primary' : 'btn-outline'}`}
            style={{ padding: '0.35rem 0.85rem', fontSize: '0.8rem', borderRadius: 'var(--radius-full)' }}
          >
            <Car size={13} />
            7 Seater
          </button>

          {(femaleOnly || capacityFilters.size > 0 || selectedSort !== 'default') && (
            <button
              type="button"
              onClick={resetFilters}
              style={{
                fontSize: '0.75rem',
                color: 'var(--red)',
                marginLeft: 'auto',
                fontWeight: 600,
                cursor: 'pointer',
              }}
            >
              Clear filters
            </button>
          )}
        </div>

        {/* Search Results List */}
        <div>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '1rem' }}>
            <span style={{ fontWeight: 600, color: 'var(--navy)', fontSize: '0.95rem' }}>
              {sortedRides.length} {sortedRides.length === 1 ? 'ride' : 'rides'} found
            </span>
          </div>

          {loading ? (
            <div style={{ textAlign: 'center', padding: '4rem 0', color: 'var(--grey)' }}>
              Searching for available rides...
            </div>
          ) : sortedRides.length > 0 ? (
            <div
              style={{
                display: 'grid',
                gridTemplateColumns: 'repeat(auto-fit, minmax(320px, 1fr))',
                gap: '1.25rem',
              }}
            >
              {sortedRides.map((ride) => (
                <RideCard key={ride.id} ride={ride} />
              ))}
            </div>
          ) : (
            <div
              className="card"
              style={{
                textAlign: 'center',
                padding: '4rem 1.5rem',
                background: '#ffffff',
                border: '1.5px dashed var(--grey-border)',
              }}
            >
              <div
                style={{
                  width: 56,
                  height: 56,
                  borderRadius: '50%',
                  background: 'var(--bg)',
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  margin: '0 auto 1rem',
                  color: 'var(--grey-light)',
                }}
              >
                <Search size={28} />
              </div>
              <h3 style={{ fontSize: '1.2rem', fontWeight: 700, color: 'var(--navy)', marginBottom: '0.5rem' }}>
                No rides matched your filters
              </h3>
              <p style={{ color: 'var(--grey)', fontSize: '0.9rem', maxWidth: 460, margin: '0 auto 1.5rem' }}>
                Try adjusting your search locations, picking another date, or clearing vehicle capacity filters.
              </p>
              <button type="button" onClick={resetFilters} className="btn btn-secondary">
                Reset All Filters
              </button>
            </div>
          )}
        </div>
      </div>
    </div>
  );
};
