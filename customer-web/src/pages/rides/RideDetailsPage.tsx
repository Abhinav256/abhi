import React, { useState, useEffect } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import {
  Car,
  Star,
  ShieldCheck,
  CheckCircle,
  AlertCircle,
  ArrowLeft,
} from 'lucide-react';
import { api } from '../../services/api';
import { useAuth } from '../../context/AuthContext';
import type { Ride, Booking } from '../../types';
import { Modal } from '../../components/ui/Modal';
import { RatingModal } from '../../components/rides/RatingModal';

export const RideDetailsPage: React.FC = () => {
  const { rideId } = useParams<{ rideId: string }>();
  const navigate = useNavigate();
  const { user } = useAuth();

  const [ride, setRide] = useState<Ride | null>(null);
  const [bookings, setBookings] = useState<Booking[]>([]);
  const [loading, setLoading] = useState(true);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const [actionSuccess, setActionSuccess] = useState<string | null>(null);

  // Driver action confirmation modals
  const [isCancelModalOpen, setIsCancelModalOpen] = useState(false);
  const [isCompleteModalOpen, setIsCompleteModalOpen] = useState(false);
  const [submittingAction, setSubmittingAction] = useState(false);

  // Rating modal after ride completion
  const [isRatingModalOpen, setIsRatingModalOpen] = useState(false);

  const loadRide = async () => {
    if (!rideId) return;
    try {
      setLoading(true);
      setErrorMessage(null);
      const data = await api.getRideDetail(rideId);
      setRide(data);

      // Check if current user is the driver
      const currentUserId = api.getUserId();
      if (currentUserId && data.driver_id === currentUserId) {
        try {
          const rideBookings = await api.getRideBookings(rideId);
          setBookings(rideBookings);
        } catch {
          // ignore booking query failure
        }
      }
    } catch (err: any) {
      setErrorMessage(err.message || 'Failed to load ride details');
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    loadRide();
  }, [rideId]);

  const isDriver = !!(user && ride && (user.id === ride.driver_id || api.getUserId() === ride.driver_id));

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
      return d.toLocaleDateString('en-IN', { weekday: 'short', day: 'numeric', month: 'short', year: 'numeric' });
    } catch {
      return dateStr;
    }
  };

  const handleCancelRide = async () => {
    if (!rideId) return;
    try {
      setSubmittingAction(true);
      await api.cancelRide(rideId);
      setActionSuccess('Ride cancelled successfully.');
      setIsCancelModalOpen(false);
      await loadRide();
    } catch (err: any) {
      setErrorMessage(err.message || 'Failed to cancel ride');
    } finally {
      setSubmittingAction(false);
    }
  };

  const handleCompleteRide = async () => {
    if (!rideId) return;
    try {
      setSubmittingAction(true);
      await api.completeRide(rideId);
      setActionSuccess('Ride marked as completed!');
      setIsCompleteModalOpen(false);
      await loadRide();
      // If passengers booked, show rating dialog
      if (bookings.some((b) => b.status === 'confirmed' || b.status === 'completed')) {
        setIsRatingModalOpen(true);
      }
    } catch (err: any) {
      setErrorMessage(err.message || 'Failed to complete ride');
    } finally {
      setSubmittingAction(false);
    }
  };

  if (loading) {
    return (
      <div style={{ textAlign: 'center', padding: '5rem 0', color: 'var(--grey)' }}>
        Loading ride details...
      </div>
    );
  }

  if (!ride) {
    return (
      <div className="app-container" style={{ padding: '3rem 0', textAlign: 'center' }}>
        <h2>Ride not found</h2>
        <button type="button" onClick={() => navigate('/search')} className="btn btn-primary" style={{ marginTop: '1rem' }}>
          Back to Search
        </button>
      </div>
    );
  }

  const driverName = ride.driver_name || ride.driver?.full_name || 'Verified Driver';
  const driverRating = ride.driver_rating || ride.driver?.average_rating || '5.0';
  const driverPhoto = ride.driver_photo || ride.driver?.driver_selfie_url || ride.driver?.profile_photo;
  const vehicle = ride.vehicle;

  return (
    <div className="animate-fade-in" style={{ padding: '1.5rem 0' }}>
      <div className="app-container" style={{ maxWidth: 840 }}>
        {/* Back Link */}
        <button
          type="button"
          onClick={() => navigate(-1)}
          style={{
            display: 'inline-flex',
            alignItems: 'center',
            gap: '0.4rem',
            color: 'var(--grey)',
            fontWeight: 600,
            fontSize: '0.9rem',
            marginBottom: '1rem',
            cursor: 'pointer',
          }}
        >
          <ArrowLeft size={16} />
          Back
        </button>

        {actionSuccess && (
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
            <span>{actionSuccess}</span>
          </div>
        )}

        {errorMessage && (
          <div
            style={{
              background: 'var(--red-bg)',
              color: 'var(--red)',
              padding: '0.85rem 1rem',
              borderRadius: 'var(--radius-md)',
              marginBottom: '1.25rem',
              display: 'flex',
              alignItems: 'center',
              gap: '0.5rem',
              fontWeight: 500,
            }}
          >
            <AlertCircle size={18} />
            <span>{errorMessage}</span>
          </div>
        )}

        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(320px, 1fr))', gap: '1.5rem' }}>
          {/* Main Route Details Card */}
          <div
            className="card"
            style={{
              background: '#ffffff',
              border: '1.5px solid var(--grey-border)',
              display: 'flex',
              flexDirection: 'column',
              gap: '1.5rem',
            }}
          >
            {/* Header: Date & Status */}
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
              <div>
                <span style={{ fontSize: '0.85rem', color: 'var(--grey)', fontWeight: 600 }}>
                  {formatDate(ride.journey_date)}
                </span>
                <div style={{ fontSize: '1.5rem', fontWeight: 800, color: 'var(--navy)' }}>
                  {formatTime(ride.departure_time)}
                </div>
              </div>

              <span
                className={`badge ${
                  ride.status === 'completed'
                    ? 'badge-green'
                    : ride.status === 'cancelled'
                    ? 'badge-red'
                    : 'badge-blue'
                }`}
                style={{ fontSize: '0.85rem', padding: '0.35rem 0.75rem' }}
              >
                {ride.status}
              </span>
            </div>

            {/* Route Timeline */}
            <div style={{ display: 'flex', flexDirection: 'column', gap: '1.25rem', position: 'relative', paddingLeft: '1.5rem' }}>
              {/* Vertical line connecting points */}
              <div
                style={{
                  position: 'absolute',
                  left: 6,
                  top: 10,
                  bottom: 10,
                  width: 2,
                  background: 'var(--grey-border)',
                }}
              />

              {/* Origin */}
              <div style={{ position: 'relative' }}>
                <div
                  style={{
                    position: 'absolute',
                    left: -20,
                    top: 4,
                    width: 12,
                    height: 12,
                    borderRadius: '50%',
                    background: 'var(--green)',
                  }}
                />
                <span style={{ fontSize: '0.75rem', color: 'var(--grey)', textTransform: 'uppercase', fontWeight: 700 }}>
                  Pickup Origin
                </span>
                <div style={{ fontSize: '1.1rem', fontWeight: 700, color: 'var(--navy)' }}>
                  {ride.origin}
                </div>
              </div>

              {/* Destination */}
              <div style={{ position: 'relative' }}>
                <div
                  style={{
                    position: 'absolute',
                    left: -20,
                    top: 4,
                    width: 12,
                    height: 12,
                    borderRadius: '50%',
                    background: 'var(--blue)',
                  }}
                />
                <span style={{ fontSize: '0.75rem', color: 'var(--grey)', textTransform: 'uppercase', fontWeight: 700 }}>
                  Drop Destination
                </span>
                <div style={{ fontSize: '1.1rem', fontWeight: 700, color: 'var(--navy)' }}>
                  {ride.destination}
                </div>
              </div>
            </div>

            {/* Price & Seats Summary */}
            <div
              style={{
                display: 'flex',
                justifyContent: 'space-between',
                background: 'var(--bg)',
                padding: '1rem',
                borderRadius: 'var(--radius-lg)',
                border: '1px solid var(--grey-border)',
              }}
            >
              <div>
                <span style={{ fontSize: '0.8rem', color: 'var(--grey)', fontWeight: 600 }}>Fare per seat</span>
                <div style={{ fontSize: '1.5rem', fontWeight: 800, color: 'var(--blue)' }}>
                  ₹{ride.price_per_seat}
                </div>
              </div>

              <div style={{ textAlign: 'right' }}>
                <span style={{ fontSize: '0.8rem', color: 'var(--grey)', fontWeight: 600 }}>Seats Remaining</span>
                <div style={{ fontSize: '1.25rem', fontWeight: 800, color: 'var(--navy)' }}>
                  {ride.available_seats} of {ride.total_seats || 4}
                </div>
              </div>
            </div>

            {/* Trip Notes if any */}
            {ride.notes && (
              <div style={{ fontSize: '0.9rem', color: 'var(--grey)', background: '#F8FAFC', padding: '0.85rem', borderRadius: 'var(--radius-md)' }}>
                <strong style={{ color: 'var(--navy)' }}>Driver notes: </strong>
                {ride.notes}
              </div>
            )}

            {/* Action Buttons */}
            {isDriver ? (
              <div style={{ display: 'flex', gap: '0.75rem', marginTop: '0.5rem' }}>
                {ride.status === 'active' && (
                  <>
                    <button
                      type="button"
                      onClick={() => setIsCompleteModalOpen(true)}
                      className="btn btn-success"
                      style={{ flex: 1 }}
                    >
                      <CheckCircle size={18} />
                      Complete Ride
                    </button>
                    <button
                      type="button"
                      onClick={() => setIsCancelModalOpen(true)}
                      className="btn btn-danger"
                      style={{ flex: 1 }}
                    >
                      Cancel Ride
                    </button>
                  </>
                )}
              </div>
            ) : (
              ride.status === 'active' &&
              ride.available_seats > 0 && (
                <button
                  type="button"
                  className="btn btn-primary"
                  onClick={() => navigate(`/rides/${ride.id}/book`)}
                  style={{ width: '100%', padding: '0.85rem', fontSize: '1rem' }}
                >
                  Book Seat(s) Now
                </button>
              )
            )}
          </div>

          {/* Right Column: Driver & Vehicle Cards */}
          <div style={{ display: 'flex', flexDirection: 'column', gap: '1.25rem' }}>
            {/* Driver Profile Card */}
            <div className="card" style={{ background: '#ffffff', border: '1.5px solid var(--grey-border)' }}>
              <h3 style={{ fontSize: '1rem', fontWeight: 700, color: 'var(--navy)', marginBottom: '1rem' }}>
                Driver Information
              </h3>
              <div style={{ display: 'flex', alignItems: 'center', gap: '1rem' }}>
                {driverPhoto ? (
                  <img
                    src={driverPhoto}
                    alt={driverName}
                    style={{ width: 56, height: 56, borderRadius: '50%', objectFit: 'cover' }}
                  />
                ) : (
                  <div
                    style={{
                      width: 56,
                      height: 56,
                      borderRadius: '50%',
                      background: 'var(--bg-header)',
                      color: 'var(--blue)',
                      display: 'flex',
                      alignItems: 'center',
                      justifyContent: 'center',
                      fontWeight: 700,
                      fontSize: '1.2rem',
                    }}
                  >
                    {driverName.charAt(0)}
                  </div>
                )}

                <div>
                  <div style={{ display: 'flex', alignItems: 'center', gap: '0.35rem' }}>
                    <h4 style={{ fontWeight: 700, color: 'var(--navy)', fontSize: '1.05rem' }}>
                      {driverName}
                    </h4>
                    <ShieldCheck size={16} color="var(--green)" />
                  </div>
                  <div style={{ display: 'flex', alignItems: 'center', gap: '0.35rem', marginTop: '0.2rem' }}>
                    <Star size={14} fill="var(--amber)" color="var(--amber)" />
                    <span style={{ fontWeight: 700, fontSize: '0.875rem', color: 'var(--navy)' }}>
                      {driverRating}
                    </span>
                    <span style={{ fontSize: '0.75rem', color: 'var(--grey)' }}>Verified Profile</span>
                  </div>
                </div>
              </div>
            </div>

            {/* Vehicle Details Card */}
            <div className="card" style={{ background: '#ffffff', border: '1.5px solid var(--grey-border)' }}>
              <h3 style={{ fontSize: '1rem', fontWeight: 700, color: 'var(--navy)', marginBottom: '1rem' }}>
                Vehicle Details
              </h3>
              <div style={{ display: 'flex', alignItems: 'center', gap: '0.75rem' }}>
                <div
                  style={{
                    width: 44,
                    height: 44,
                    borderRadius: 'var(--radius-md)',
                    background: 'var(--bg-header)',
                    color: 'var(--blue)',
                    display: 'flex',
                    alignItems: 'center',
                    justifyContent: 'center',
                  }}
                >
                  <Car size={24} />
                </div>
                <div>
                  <div style={{ fontWeight: 700, color: 'var(--navy)' }}>
                    {vehicle?.model || ride.vehicle_model || 'Standard Vehicle'}
                  </div>
                  <div style={{ fontSize: '0.85rem', color: 'var(--grey)', fontWeight: 600 }}>
                    {vehicle?.vehicle_number || ride.vehicle_number || 'Registered'}
                  </div>
                </div>
              </div>
            </div>

            {/* Passenger Bookings (if driver) */}
            {isDriver && (
              <div className="card" style={{ background: '#ffffff', border: '1.5px solid var(--grey-border)' }}>
                <h3 style={{ fontSize: '1rem', fontWeight: 700, color: 'var(--navy)', marginBottom: '0.75rem' }}>
                  Confirmed Passengers ({bookings.length})
                </h3>
                {bookings.length > 0 ? (
                  <div style={{ display: 'flex', flexDirection: 'column', gap: '0.5rem' }}>
                    {bookings.map((b) => (
                      <div
                        key={b.id}
                        style={{
                          padding: '0.65rem 0.75rem',
                          borderRadius: 'var(--radius-md)',
                          background: 'var(--bg)',
                          display: 'flex',
                          justifyContent: 'space-between',
                          alignItems: 'center',
                        }}
                      >
                        <div>
                          <div style={{ fontWeight: 600, fontSize: '0.875rem', color: 'var(--navy)' }}>
                            {b.passenger?.full_name || 'Passenger'}
                          </div>
                          <span style={{ fontSize: '0.75rem', color: 'var(--grey)' }}>
                            {b.seats_booked} seat(s) • ₹{b.total_price}
                          </span>
                        </div>
                        <span className="badge badge-green">{b.status}</span>
                      </div>
                    ))}
                  </div>
                ) : (
                  <p style={{ color: 'var(--grey)', fontSize: '0.85rem' }}>
                    No bookings yet. Empty seats are open for passengers to book.
                  </p>
                )}
              </div>
            )}
          </div>
        </div>

        {/* Cancel Confirmation Modal */}
        <Modal
          isOpen={isCancelModalOpen}
          onClose={() => setIsCancelModalOpen(false)}
          title="Cancel this ride?"
          maxWidth="440px"
        >
          <p style={{ color: 'var(--navy)', marginBottom: '1.5rem', fontSize: '0.95rem' }}>
            Are you sure you want to cancel this scheduled ride? Any booked passengers will be notified immediately.
          </p>
          <div style={{ display: 'flex', justifyContent: 'flex-end', gap: '0.75rem' }}>
            <button
              type="button"
              onClick={() => setIsCancelModalOpen(false)}
              className="btn btn-outline"
              disabled={submittingAction}
            >
              Keep Ride
            </button>
            <button
              type="button"
              onClick={handleCancelRide}
              className="btn btn-danger"
              disabled={submittingAction}
            >
              {submittingAction ? 'Cancelling...' : 'Confirm Cancellation'}
            </button>
          </div>
        </Modal>

        {/* Complete Confirmation Modal */}
        <Modal
          isOpen={isCompleteModalOpen}
          onClose={() => setIsCompleteModalOpen(false)}
          title="Mark Ride as Completed?"
          maxWidth="440px"
        >
          <p style={{ color: 'var(--navy)', marginBottom: '1.5rem', fontSize: '0.95rem' }}>
            Confirm that your journey has concluded. Passengers will receive payment confirmation and prompt to rate your trip.
          </p>
          <div style={{ display: 'flex', justifyContent: 'flex-end', gap: '0.75rem' }}>
            <button
              type="button"
              onClick={() => setIsCompleteModalOpen(false)}
              className="btn btn-outline"
              disabled={submittingAction}
            >
              Not Yet
            </button>
            <button
              type="button"
              onClick={handleCompleteRide}
              className="btn btn-primary"
              disabled={submittingAction}
            >
              {submittingAction ? 'Completing...' : 'Yes, Complete Ride'}
            </button>
          </div>
        </Modal>

        {/* Post-ride Rating Modal */}
        {isRatingModalOpen && rideId && (
          <RatingModal
            isOpen={true}
            onClose={() => setIsRatingModalOpen(false)}
            rideId={rideId}
            participants={bookings.map((b) => ({
              user_id: b.passenger_id,
              name: b.passenger?.full_name || 'Passenger',
              role: 'passenger',
            }))}
            onSuccess={() => {
              setIsRatingModalOpen(false);
              navigate('/my-rides');
            }}
          />
        )}
      </div>
    </div>
  );
};
