import React, { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import {
  Car,
  Users,
  CheckCircle,
  ChevronRight,
} from 'lucide-react';
import { api } from '../../services/api';
import type { Booking, Ride } from '../../types';
import { Modal } from '../../components/ui/Modal';

export const MyRidesPage: React.FC = () => {
  const navigate = useNavigate();

  const [activeTab, setActiveTab] = useState<'bookings' | 'published'>('bookings');
  const [statusFilter, setStatusFilter] = useState<'Upcoming' | 'Completed' | 'Cancelled'>('Upcoming');

  const [bookings, setBookings] = useState<Booking[]>([]);
  const [publishedRides, setPublishedRides] = useState<Ride[]>([]);
  const [loading, setLoading] = useState(true);
  const [message, setMessage] = useState<string | null>(null);

  // Cancellation modal state
  const [bookingToCancel, setBookingToCancel] = useState<Booking | null>(null);
  const [rideToCancel, setRideToCancel] = useState<Ride | null>(null);
  const [cancelling, setCancelling] = useState(false);

  const loadData = async () => {
    try {
      setLoading(true);
      const [bookingsList, ridesList] = await Promise.all([
        api.getMyBookings(),
        api.getMyRides(),
      ]);
      setBookings(bookingsList);
      setPublishedRides(ridesList);
    } catch (err: any) {
      console.error('Failed to load rides:', err);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    loadData();
  }, []);

  const handleCancelBooking = async () => {
    if (!bookingToCancel) return;
    try {
      setCancelling(true);
      await api.cancelBooking(bookingToCancel.id);
      setMessage('Booking cancelled successfully.');
      setTimeout(() => setMessage(null), 3000);
      setBookingToCancel(null);
      await loadData();
    } catch (err: any) {
      setMessage(err.message || 'Failed to cancel booking');
    } finally {
      setCancelling(false);
    }
  };

  const handleCancelRide = async () => {
    if (!rideToCancel) return;
    try {
      setCancelling(true);
      await api.cancelRide(rideToCancel.id);
      setMessage('Ride cancelled successfully.');
      setTimeout(() => setMessage(null), 3000);
      setRideToCancel(null);
      await loadData();
    } catch (err: any) {
      setMessage(err.message || 'Failed to cancel ride');
    } finally {
      setCancelling(false);
    }
  };

  const formatTime = (timeStr?: string) => {
    if (!timeStr) return '--:--';
    if (timeStr.includes('T')) {
      const parts = timeStr.split('T');
      if (parts[1]) return parts[1].substring(0, 5);
    }
    return timeStr.substring(0, 5);
  };

  const formatDate = (dateStr?: string) => {
    if (!dateStr) return '';
    try {
      const d = new Date(dateStr);
      return d.toLocaleDateString('en-IN', { weekday: 'short', day: 'numeric', month: 'short' });
    } catch {
      return dateStr;
    }
  };

  // Filter Bookings
  const filteredBookings = bookings.filter((b) => {
    const status = (b.status || '').toLowerCase();
    if (statusFilter === 'Upcoming') {
      return status === 'pending' || status === 'confirmed';
    }
    if (statusFilter === 'Completed') {
      return status === 'completed';
    }
    if (statusFilter === 'Cancelled') {
      return status === 'cancelled';
    }
    return true;
  });

  // Filter Published Rides
  const filteredPublishedRides = publishedRides.filter((r) => {
    const status = (r.status || '').toLowerCase();
    if (statusFilter === 'Upcoming') {
      return status === 'active' || status === 'draft' || status === 'selfie_uploaded' || status === 'confirmed';
    }
    if (statusFilter === 'Completed') {
      return status === 'completed';
    }
    if (statusFilter === 'Cancelled') {
      return status === 'cancelled';
    }
    return true;
  });

  return (
    <div className="animate-fade-in" style={{ padding: '1.5rem 0' }}>
      <div className="app-container">
        {/* Header */}
        <div style={{ marginBottom: '1.5rem' }}>
          <h1 style={{ fontSize: '1.75rem', fontWeight: 800, color: 'var(--navy)', marginBottom: '0.25rem' }}>
            My Rides & Bookings
          </h1>
          <p style={{ color: 'var(--grey)', fontSize: '0.95rem' }}>
            Track your journeys, bookings, and published carpools.
          </p>
        </div>

        {message && (
          <div
            style={{
              background: 'var(--emerald-bg)',
              color: 'var(--green)',
              padding: '0.85rem 1rem',
              borderRadius: 'var(--radius-md)',
              marginBottom: '1.25rem',
              display: 'flex',
              alignItems: 'center',
              gap: '0.5rem',
              fontWeight: 500,
            }}
          >
            <CheckCircle size={18} />
            <span>{message}</span>
          </div>
        )}

        {/* Tab Switcher: As Passenger vs As Driver */}
        <div
          style={{
            display: 'flex',
            borderBottom: '2px solid var(--grey-border)',
            marginBottom: '1.5rem',
            gap: '2rem',
          }}
        >
          <button
            type="button"
            onClick={() => setActiveTab('bookings')}
            style={{
              padding: '0.75rem 0.25rem',
              fontWeight: 700,
              fontSize: '1.05rem',
              color: activeTab === 'bookings' ? 'var(--blue)' : 'var(--grey)',
              borderBottom: activeTab === 'bookings' ? '3px solid var(--blue)' : '3px solid transparent',
              marginBottom: -2,
              cursor: 'pointer',
              display: 'flex',
              alignItems: 'center',
              gap: '0.5rem',
            }}
          >
            <Users size={18} />
            My Bookings ({bookings.length})
          </button>

          <button
            type="button"
            onClick={() => setActiveTab('published')}
            style={{
              padding: '0.75rem 0.25rem',
              fontWeight: 700,
              fontSize: '1.05rem',
              color: activeTab === 'published' ? 'var(--blue)' : 'var(--grey)',
              borderBottom: activeTab === 'published' ? '3px solid var(--blue)' : '3px solid transparent',
              marginBottom: -2,
              cursor: 'pointer',
              display: 'flex',
              alignItems: 'center',
              gap: '0.5rem',
            }}
          >
            <Car size={18} />
            My Offered Rides ({publishedRides.length})
          </button>
        </div>

        {/* Status Filter Chips */}
        <div style={{ display: 'flex', gap: '0.5rem', marginBottom: '1.5rem' }}>
          {(['Upcoming', 'Completed', 'Cancelled'] as const).map((filter) => (
            <button
              key={filter}
              type="button"
              onClick={() => setStatusFilter(filter)}
              className={`btn ${statusFilter === filter ? 'btn-secondary' : 'btn-outline'}`}
              style={{ padding: '0.4rem 1rem', fontSize: '0.85rem', borderRadius: 'var(--radius-full)' }}
            >
              {filter}
            </button>
          ))}
        </div>

        {/* Content Body */}
        {loading ? (
          <div style={{ textAlign: 'center', padding: '4rem 0', color: 'var(--grey)' }}>
            Loading your rides...
          </div>
        ) : activeTab === 'bookings' ? (
          /* Tab 1: Bookings List */
          filteredBookings.length > 0 ? (
            <div
              style={{
                display: 'grid',
                gridTemplateColumns: 'repeat(auto-fit, minmax(320px, 1fr))',
                gap: '1.25rem',
              }}
            >
              {filteredBookings.map((b) => {
                const ride = b.ride;
                return (
                  <div
                    key={b.id}
                    className="card card-hover"
                    style={{
                      border: '1.5px solid var(--grey-border)',
                      display: 'flex',
                      flexDirection: 'column',
                      justifyContent: 'space-between',
                      gap: '1rem',
                    }}
                  >
                    <div>
                      {/* Top status & price */}
                      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: '0.75rem' }}>
                        <div>
                          <span style={{ fontSize: '0.8rem', color: 'var(--grey)', fontWeight: 600 }}>
                            {formatDate(ride?.journey_date)} • {formatTime(ride?.departure_time)}
                          </span>
                          <div style={{ fontSize: '1.1rem', fontWeight: 800, color: 'var(--navy)' }}>
                            ₹{b.total_price}
                          </div>
                        </div>

                        <span
                          className={`badge ${
                            b.status === 'completed'
                              ? 'badge-green'
                              : b.status === 'cancelled'
                              ? 'badge-red'
                              : 'badge-blue'
                          }`}
                        >
                          {b.status}
                        </span>
                      </div>

                      {/* Route */}
                      <div style={{ display: 'flex', flexDirection: 'column', gap: '0.4rem', marginBottom: '0.75rem' }}>
                        <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem', fontSize: '0.9rem', fontWeight: 600, color: 'var(--navy)' }}>
                          <span style={{ width: 8, height: 8, borderRadius: '50%', background: 'var(--green)' }} />
                          <span>{ride?.origin || 'Pickup'}</span>
                        </div>
                        <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem', fontSize: '0.9rem', fontWeight: 600, color: 'var(--navy)' }}>
                          <span style={{ width: 8, height: 8, borderRadius: '50%', background: 'var(--blue)' }} />
                          <span>{ride?.destination || 'Destination'}</span>
                        </div>
                      </div>

                      <div style={{ fontSize: '0.8rem', color: 'var(--grey)' }}>
                        Seats booked: <strong>{b.seats_booked}</strong> • Mode: <strong>{b.payment_mode || 'Cash'}</strong>
                      </div>
                    </div>

                    {/* Bottom Actions */}
                    <div
                      style={{
                        display: 'flex',
                        justifyContent: 'space-between',
                        alignItems: 'center',
                        borderTop: '1px solid var(--grey-border)',
                        paddingTop: '0.75rem',
                      }}
                    >
                      {ride?.id ? (
                        <button
                          type="button"
                          onClick={() => navigate(`/rides/${ride.id}`)}
                          style={{
                            color: 'var(--blue)',
                            fontWeight: 600,
                            fontSize: '0.85rem',
                            display: 'flex',
                            alignItems: 'center',
                            gap: '0.25rem',
                          }}
                        >
                          View Ride Details <ChevronRight size={14} />
                        </button>
                      ) : <span />}

                      {b.status === 'confirmed' && (
                        <button
                          type="button"
                          onClick={() => setBookingToCancel(b)}
                          className="btn btn-danger"
                          style={{ padding: '0.35rem 0.75rem', fontSize: '0.8rem' }}
                        >
                          Cancel Booking
                        </button>
                      )}
                    </div>
                  </div>
                );
              })}
            </div>
          ) : (
            <div
              className="card"
              style={{
                textAlign: 'center',
                padding: '4rem 1.5rem',
                border: '1.5px dashed var(--grey-border)',
                background: '#ffffff',
              }}
            >
              <Users size={36} color="var(--grey-light)" style={{ margin: '0 auto 1rem' }} />
              <h3 style={{ fontSize: '1.15rem', fontWeight: 700, color: 'var(--navy)', marginBottom: '0.35rem' }}>
                No {statusFilter.toLowerCase()} bookings
              </h3>
              <p style={{ color: 'var(--grey)', fontSize: '0.9rem', marginBottom: '1.5rem' }}>
                You have no journeys in this status category.
              </p>
              <button type="button" onClick={() => navigate('/search')} className="btn btn-primary">
                Find a Ride
              </button>
            </div>
          )
        ) : (
          /* Tab 2: Published Rides List */
          filteredPublishedRides.length > 0 ? (
            <div
              style={{
                display: 'grid',
                gridTemplateColumns: 'repeat(auto-fit, minmax(320px, 1fr))',
                gap: '1.25rem',
              }}
            >
              {filteredPublishedRides.map((r) => (
                <div
                  key={r.id}
                  className="card card-hover"
                  style={{
                    border: '1.5px solid var(--grey-border)',
                    display: 'flex',
                    flexDirection: 'column',
                    justifyContent: 'space-between',
                    gap: '1rem',
                  }}
                >
                  <div>
                    {/* Top status & price */}
                    <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: '0.75rem' }}>
                      <div>
                        <span style={{ fontSize: '0.8rem', color: 'var(--grey)', fontWeight: 600 }}>
                          {formatDate(r.journey_date)} • {formatTime(r.departure_time)}
                        </span>
                        <div style={{ fontSize: '1.1rem', fontWeight: 800, color: 'var(--navy)' }}>
                          ₹{r.price_per_seat} / seat
                        </div>
                      </div>

                      <span
                        className={`badge ${
                          r.status === 'completed'
                            ? 'badge-green'
                            : r.status === 'cancelled'
                            ? 'badge-red'
                            : 'badge-blue'
                        }`}
                      >
                        {r.status}
                      </span>
                    </div>

                    {/* Route */}
                    <div style={{ display: 'flex', flexDirection: 'column', gap: '0.4rem', marginBottom: '0.75rem' }}>
                      <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem', fontSize: '0.9rem', fontWeight: 600, color: 'var(--navy)' }}>
                        <span style={{ width: 8, height: 8, borderRadius: '50%', background: 'var(--green)' }} />
                        <span>{r.origin}</span>
                      </div>
                      <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem', fontSize: '0.9rem', fontWeight: 600, color: 'var(--navy)' }}>
                        <span style={{ width: 8, height: 8, borderRadius: '50%', background: 'var(--blue)' }} />
                        <span>{r.destination}</span>
                      </div>
                    </div>

                    <div style={{ fontSize: '0.8rem', color: 'var(--grey)' }}>
                      Vehicle: <strong>{r.vehicle?.model || r.vehicle_model || 'Vehicle'}</strong> • Available seats: <strong>{r.available_seats}</strong>
                    </div>
                  </div>

                  {/* Actions */}
                  <div
                    style={{
                      display: 'flex',
                      justifyContent: 'space-between',
                      alignItems: 'center',
                      borderTop: '1px solid var(--grey-border)',
                      paddingTop: '0.75rem',
                    }}
                  >
                    <button
                      type="button"
                      onClick={() => navigate(`/rides/${r.id}`)}
                      style={{
                        color: 'var(--blue)',
                        fontWeight: 600,
                        fontSize: '0.85rem',
                        display: 'flex',
                        alignItems: 'center',
                        gap: '0.25rem',
                      }}
                    >
                      Manage Ride <ChevronRight size={14} />
                    </button>

                    {r.status === 'active' && (
                      <button
                        type="button"
                        onClick={() => setRideToCancel(r)}
                        className="btn btn-danger"
                        style={{ padding: '0.35rem 0.75rem', fontSize: '0.8rem' }}
                      >
                        Cancel Ride
                      </button>
                    )}
                  </div>
                </div>
              ))}
            </div>
          ) : (
            <div
              className="card"
              style={{
                textAlign: 'center',
                padding: '4rem 1.5rem',
                border: '1.5px dashed var(--grey-border)',
                background: '#ffffff',
              }}
            >
              <Car size={36} color="var(--grey-light)" style={{ margin: '0 auto 1rem' }} />
              <h3 style={{ fontSize: '1.15rem', fontWeight: 700, color: 'var(--navy)', marginBottom: '0.35rem' }}>
                No {statusFilter.toLowerCase()} rides
              </h3>
              <p style={{ color: 'var(--grey)', fontSize: '0.9rem', marginBottom: '1.5rem' }}>
                You have not offered any rides matching this status.
              </p>
              <button type="button" onClick={() => navigate('/create-ride')} className="btn btn-primary">
                Offer a Ride
              </button>
            </div>
          )
        )}

        {/* Cancel Booking Modal */}
        <Modal
          isOpen={!!bookingToCancel}
          onClose={() => setBookingToCancel(null)}
          title="Cancel this booking?"
          maxWidth="440px"
        >
          <p style={{ color: 'var(--navy)', marginBottom: '1.5rem', fontSize: '0.95rem' }}>
            Are you sure you want to cancel your seat reservation? Your seats will become available for other commuters.
          </p>
          <div style={{ display: 'flex', justifyContent: 'flex-end', gap: '0.75rem' }}>
            <button
              type="button"
              onClick={() => setBookingToCancel(null)}
              className="btn btn-outline"
              disabled={cancelling}
            >
              Keep Booking
            </button>
            <button
              type="button"
              onClick={handleCancelBooking}
              className="btn btn-danger"
              disabled={cancelling}
            >
              {cancelling ? 'Cancelling...' : 'Confirm Cancellation'}
            </button>
          </div>
        </Modal>

        {/* Cancel Ride Modal */}
        <Modal
          isOpen={!!rideToCancel}
          onClose={() => setRideToCancel(null)}
          title="Cancel this offered ride?"
          maxWidth="440px"
        >
          <p style={{ color: 'var(--navy)', marginBottom: '1.5rem', fontSize: '0.95rem' }}>
            Are you sure you want to cancel this ride? All passengers booked on this trip will be notified.
          </p>
          <div style={{ display: 'flex', justifyContent: 'flex-end', gap: '0.75rem' }}>
            <button
              type="button"
              onClick={() => setRideToCancel(null)}
              className="btn btn-outline"
              disabled={cancelling}
            >
              Keep Ride
            </button>
            <button
              type="button"
              onClick={handleCancelRide}
              className="btn btn-danger"
              disabled={cancelling}
            >
              {cancelling ? 'Cancelling...' : 'Confirm Cancellation'}
            </button>
          </div>
        </Modal>
      </div>
    </div>
  );
};
