import React, { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import {
  Search,
  PlusCircle,
  TrendingUp,
  Star,
  IndianRupee,
  Calendar,
  ArrowRight,
  ShieldCheck,
} from 'lucide-react';
import { useAuth } from '../../context/AuthContext';
import { api } from '../../services/api';
import type { Ride } from '../../types';
import { RideCard } from '../../components/rides/RideCard';

export const HomePage: React.FC = () => {
  const { user, isAuthenticated } = useAuth();
  const navigate = useNavigate();

  const [upcomingRides, setUpcomingRides] = useState<Ride[]>([]);
  const [loadingRides, setLoadingRides] = useState(true);

  // Greeting based on time of day
  const getGreeting = () => {
    const hour = new Date().getHours();
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  };

  useEffect(() => {
    if (!isAuthenticated) {
      setLoadingRides(false);
      return;
    }

    const fetchUpcomingRides = async () => {
      try {
        setLoadingRides(true);
        const [myBookings, myCreatedRides] = await Promise.all([
          api.getMyBookings(),
          api.getMyRides(),
        ]);

        const validStatuses = new Set(['active', 'confirmed', 'published', 'selfie_uploaded']);
        const now = new Date();

        // Collect rides from bookings (strictly exclude completed/cancelled)
        const bookedRides: Ride[] = myBookings
          .filter((b) => {
            if (!b.ride) return false;
            const rStatus = (b.ride.status || '').toLowerCase();
            const bStatus = (b.booking_status || b.status || '').toLowerCase();
            if (rStatus === 'completed' || rStatus === 'cancelled' || rStatus === 'canceled') return false;
            if (bStatus === 'completed' || bStatus === 'cancelled' || bStatus === 'canceled') return false;
            return validStatuses.has(rStatus) || rStatus === 'active';
          })
          .map((b) => b.ride as Ride);

        // Collect created rides (strictly exclude completed/cancelled)
        const createdRides: Ride[] = myCreatedRides.filter((r) => {
          const status = (r.status || '').toLowerCase();
          if (status === 'completed' || status === 'cancelled' || status === 'canceled') return false;
          return validStatuses.has(status);
        });

        const combined = [...bookedRides, ...createdRides];

        // Deduplicate and filter future rides
        const uniqueMap = new Map<string, Ride>();
        for (const ride of combined) {
          if (!ride.id) continue;
          if (ride.journey_date) {
            const rideDate = new Date(`${ride.journey_date}T${ride.departure_time || '23:59:59'}`);
            // Exclude past rides
            if (rideDate.getTime() + 24 * 60 * 60 * 1000 < now.getTime()) {
              continue;
            }
          }
          uniqueMap.set(ride.id, ride);
        }

        const sorted = Array.from(uniqueMap.values()).sort((a, b) => {
          return new Date(a.journey_date).getTime() - new Date(b.journey_date).getTime();
        });

        setUpcomingRides(sorted.slice(0, 4));
      } catch (err) {
        console.error('Error fetching upcoming rides:', err);
      } finally {
        setLoadingRides(false);
      }
    };

    fetchUpcomingRides();
  }, [isAuthenticated]);

  const displayName = user?.full_name?.split(' ')[0] || 'Friend';

  return (
    <div className="animate-fade-in" style={{ padding: '1.5rem 0' }}>
      <div className="app-container">
        {/* Hero & Greeting Section */}
        <section
          style={{
            background: 'linear-gradient(135deg, #0B1B3B 0%, #102A6B 100%)',
            borderRadius: 'var(--radius-2xl)',
            padding: '2.5rem 2rem',
            color: '#ffffff',
            boxShadow: 'var(--shadow-lg)',
            marginBottom: '2rem',
            position: 'relative',
            overflow: 'hidden',
          }}
        >
          {/* Subtle decorative circles */}
          <div
            style={{
              position: 'absolute',
              top: -60,
              right: -60,
              width: 240,
              height: 240,
              borderRadius: '50%',
              background: 'radial-gradient(circle, rgba(14, 138, 106, 0.25) 0%, transparent 70%)',
            }}
          />
          <div
            style={{
              position: 'absolute',
              bottom: -40,
              left: 200,
              width: 180,
              height: 180,
              borderRadius: '50%',
              background: 'radial-gradient(circle, rgba(29, 110, 229, 0.25) 0%, transparent 70%)',
            }}
          />

          <div style={{ position: 'relative', zIndex: 1, maxWidth: 640 }}>
            <span
              style={{
                display: 'inline-flex',
                alignItems: 'center',
                gap: '0.4rem',
                fontSize: '0.85rem',
                fontWeight: 600,
                color: '#8EC5F5',
                textTransform: 'uppercase',
                letterSpacing: '1px',
                marginBottom: '0.5rem',
              }}
            >
              <ShieldCheck size={16} color="var(--emerald-dark)" />
              Verified Community Carpooling
            </span>

            <h1
              style={{
                fontSize: 'clamp(1.75rem, 3.5vw, 2.5rem)',
                fontWeight: 800,
                lineHeight: 1.2,
                margin: '0.25rem 0 0.75rem',
                letterSpacing: '-0.5px',
              }}
            >
              {getGreeting()},{' '}
              <span style={{ color: '#60A5FA' }}>{displayName}!</span>
            </h1>

            <p style={{ fontSize: '1.05rem', color: '#D1D5DB', marginBottom: '1.5rem' }}>
              Where are you heading today? Split fuel costs, commute together, and travel with peace of mind.
            </p>

            <div style={{ display: 'flex', gap: '0.85rem', flexWrap: 'wrap' }}>
              <button
                type="button"
                className="btn btn-primary"
                onClick={() => navigate('/search')}
                style={{
                  background: 'linear-gradient(135deg, var(--blue-accent), var(--blue))',
                  border: 'none',
                }}
              >
                <Search size={18} />
                Find a Ride
              </button>
              <button
                type="button"
                className="btn"
                onClick={() => navigate('/create-ride')}
                style={{
                  background: 'rgba(255, 255, 255, 0.12)',
                  color: '#ffffff',
                  border: '1px solid rgba(255, 255, 255, 0.2)',
                  backdropFilter: 'blur(8px)',
                }}
              >
                <PlusCircle size={18} />
                Offer a Ride
              </button>
            </div>
          </div>
        </section>

        {/* 3 Statistics Cards */}
        <section
          style={{
            display: 'grid',
            gridTemplateColumns: 'repeat(auto-fit, minmax(240px, 1fr))',
            gap: '1.25rem',
            marginBottom: '2rem',
          }}
        >
          {/* Stat 1: Rides */}
          <div
            className="card card-hover"
            style={{
              display: 'flex',
              alignItems: 'center',
              gap: '1rem',
              background: '#ffffff',
            }}
          >
            <div
              style={{
                width: 48,
                height: 48,
                borderRadius: 'var(--radius-lg)',
                background: 'var(--rides-bg)',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                color: 'var(--blue)',
                flexShrink: 0,
              }}
            >
              <TrendingUp size={24} />
            </div>
            <div>
              <div style={{ fontSize: '1.5rem', fontWeight: 800, color: 'var(--navy)' }}>
                {user?.rides_taken ?? upcomingRides.length}
              </div>
              <div style={{ fontSize: '0.85rem', color: 'var(--grey)', fontWeight: 500 }}>
                Rides Completed
              </div>
            </div>
          </div>

          {/* Stat 2: Rating */}
          <div
            className="card card-hover"
            style={{
              display: 'flex',
              alignItems: 'center',
              gap: '1rem',
              background: '#ffffff',
            }}
          >
            <div
              style={{
                width: 48,
                height: 48,
                borderRadius: 'var(--radius-lg)',
                background: 'var(--amber-bg)',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                color: 'var(--amber-text)',
                flexShrink: 0,
              }}
            >
              <Star size={24} fill="var(--amber-text)" />
            </div>
            <div>
              <div style={{ fontSize: '1.5rem', fontWeight: 800, color: 'var(--navy)' }}>
                {user?.average_rating ? Number(user.average_rating).toFixed(1) : '5.0'}★
              </div>
              <div style={{ fontSize: '0.85rem', color: 'var(--grey)', fontWeight: 500 }}>
                Community Rating
              </div>
            </div>
          </div>

          {/* Stat 3: Money Saved / Shared */}
          <div
            className="card card-hover"
            style={{
              display: 'flex',
              alignItems: 'center',
              gap: '1rem',
              background: '#ffffff',
            }}
          >
            <div
              style={{
                width: 48,
                height: 48,
                borderRadius: 'var(--radius-lg)',
                background: 'var(--emerald-bg)',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                color: 'var(--green)',
                flexShrink: 0,
              }}
            >
              <IndianRupee size={24} />
            </div>
            <div>
              <div style={{ fontSize: '1.5rem', fontWeight: 800, color: 'var(--navy)' }}>
                ₹{user?.money_saved ?? 850}
              </div>
              <div style={{ fontSize: '0.85rem', color: 'var(--grey)', fontWeight: 500 }}>
                Fuel Expenses Saved
              </div>
            </div>
          </div>
        </section>

        {/* 2 Main Action Cards */}
        <section
          style={{
            display: 'grid',
            gridTemplateColumns: 'repeat(auto-fit, minmax(320px, 1fr))',
            gap: '1.5rem',
            marginBottom: '2.5rem',
          }}
        >
          {/* Create Ride Card */}
          <div
            className="card card-hover"
            onClick={() => navigate('/create-ride')}
            style={{
              cursor: 'pointer',
              background: 'linear-gradient(135deg, #EAF3FF 0%, #FFFFFF 100%)',
              border: '2px solid rgba(11, 79, 216, 0.15)',
              display: 'flex',
              flexDirection: 'column',
              justifyContent: 'space-between',
              minHeight: 180,
            }}
          >
            <div>
              <div
                style={{
                  width: 44,
                  height: 44,
                  borderRadius: 'var(--radius-lg)',
                  background: 'var(--blue)',
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  color: '#ffffff',
                  marginBottom: '1rem',
                }}
              >
                <PlusCircle size={22} />
              </div>
              <h3 style={{ fontSize: '1.25rem', fontWeight: 700, color: 'var(--navy)', marginBottom: '0.4rem' }}>
                Offer Empty Seats
              </h3>
              <p style={{ color: 'var(--grey)', fontSize: '0.9rem' }}>
                Driving somewhere? Publish your route, choose co-passengers, and recover your petrol costs.
              </p>
            </div>
            <div
              style={{
                display: 'flex',
                alignItems: 'center',
                gap: '0.4rem',
                color: 'var(--blue)',
                fontWeight: 700,
                fontSize: '0.9rem',
                marginTop: '1rem',
              }}
            >
              <span>Create a ride</span>
              <ArrowRight size={16} />
            </div>
          </div>

          {/* Search Ride Card */}
          <div
            className="card card-hover"
            onClick={() => navigate('/search')}
            style={{
              cursor: 'pointer',
              background: 'linear-gradient(135deg, #E6F7F2 0%, #FFFFFF 100%)',
              border: '2px solid rgba(14, 138, 106, 0.15)',
              display: 'flex',
              flexDirection: 'column',
              justifyContent: 'space-between',
              minHeight: 180,
            }}
          >
            <div>
              <div
                style={{
                  width: 44,
                  height: 44,
                  borderRadius: 'var(--radius-lg)',
                  background: 'var(--green)',
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  color: '#ffffff',
                  marginBottom: '1rem',
                }}
              >
                <Search size={22} />
              </div>
              <h3 style={{ fontSize: '1.25rem', fontWeight: 700, color: 'var(--navy)', marginBottom: '0.4rem' }}>
                Find Shared Rides
              </h3>
              <p style={{ color: 'var(--grey)', fontSize: '0.9rem' }}>
                Traveling to work or across cities? Connect with verified commuters heading your way.
              </p>
            </div>
            <div
              style={{
                display: 'flex',
                alignItems: 'center',
                gap: '0.4rem',
                color: 'var(--green)',
                fontWeight: 700,
                fontSize: '0.9rem',
                marginTop: '1rem',
              }}
            >
              <span>Search rides</span>
              <ArrowRight size={16} />
            </div>
          </div>
        </section>

        {/* Upcoming Rides Section */}
        <section style={{ marginBottom: '2rem' }}>
          <div
            style={{
              display: 'flex',
              justifyContent: 'space-between',
              alignItems: 'center',
              marginBottom: '1rem',
            }}
          >
            <div>
              <h2 style={{ fontSize: '1.35rem', fontWeight: 700, color: 'var(--navy)' }}>
                Your Upcoming Trips
              </h2>
              <p style={{ fontSize: '0.875rem', color: 'var(--grey)' }}>
                Active rides you have scheduled or booked
              </p>
            </div>
            {upcomingRides.length > 0 && (
              <button
                type="button"
                onClick={() => navigate('/my-rides')}
                style={{
                  color: 'var(--blue)',
                  fontWeight: 600,
                  fontSize: '0.9rem',
                  display: 'flex',
                  alignItems: 'center',
                  gap: '0.25rem',
                }}
              >
                View all <ArrowRight size={14} />
              </button>
            )}
          </div>

          {loadingRides ? (
            <div style={{ textAlign: 'center', padding: '3rem 0', color: 'var(--grey)' }}>
              Loading upcoming trips...
            </div>
          ) : upcomingRides.length > 0 ? (
            <div
              style={{
                display: 'grid',
                gridTemplateColumns: 'repeat(auto-fit, minmax(320px, 1fr))',
                gap: '1.25rem',
              }}
            >
              {upcomingRides.map((ride) => (
                <RideCard key={ride.id} ride={ride} />
              ))}
            </div>
          ) : (
            <div
              className="card"
              style={{
                textAlign: 'center',
                padding: '3rem 1.5rem',
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
                <Calendar size={28} />
              </div>
              <h3 style={{ fontSize: '1.15rem', fontWeight: 700, color: 'var(--navy)', marginBottom: '0.35rem' }}>
                No Upcoming Trips
              </h3>
              <p style={{ color: 'var(--grey)', fontSize: '0.9rem', maxWidth: 420, margin: '0 auto 1.5rem' }}>
                Ready to travel? Search for available rides matching your route or publish your empty vehicle seats.
              </p>
              <div style={{ display: 'flex', justifyContent: 'center', gap: '0.75rem' }}>
                <button
                  type="button"
                  className="btn btn-secondary"
                  onClick={() => navigate('/search')}
                >
                  <Search size={16} />
                  Find a Ride
                </button>
                <button
                  type="button"
                  className="btn btn-primary"
                  onClick={() => navigate('/create-ride')}
                >
                  <PlusCircle size={16} />
                  Offer a Ride
                </button>
              </div>
            </div>
          )}
        </section>
      </div>
    </div>
  );
};
