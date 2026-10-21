import React, { useState, useEffect } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import {
  CheckCircle,
  AlertCircle,
  ArrowLeft,
  CreditCard,
  Banknote,
} from 'lucide-react';
import { api } from '../../services/api';
import { useAuth } from '../../context/AuthContext';
import type { Ride, Passenger } from '../../types';

export const BookRidePage: React.FC = () => {
  const { rideId } = useParams<{ rideId: string }>();
  const navigate = useNavigate();
  const { user } = useAuth();

  const [ride, setRide] = useState<Ride | null>(null);
  const [loading, setLoading] = useState(true);
  const [selectedSeats, setSelectedSeats] = useState<number>(1);
  const [paymentMode, setPaymentMode] = useState<'cash' | 'upi'>('cash');
  const [passengers, setPassengers] = useState<Passenger[]>([
    { name: '', age: 25, gender: 'male' },
  ]);

  const [submitting, setSubmitting] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const [bookingSuccess, setBookingSuccess] = useState<string | null>(null);

  useEffect(() => {
    if (!rideId) return;

    const fetchRide = async () => {
      try {
        setLoading(true);
        const data = await api.getRideDetail(rideId);
        setRide(data);
        if (user) {
          setPassengers([
            {
              name: user.full_name || '',
              age: 26,
              gender: (user.gender as any) || 'male',
            },
          ]);
        }
      } catch (err: any) {
        setErrorMessage(err.message || 'Failed to load ride details');
      } finally {
        setLoading(false);
      }
    };

    fetchRide();
  }, [rideId, user]);

  const handleSeatChange = (count: number) => {
    setSelectedSeats(count);
    setPassengers((prev) => {
      const updated = [...prev];
      if (count > updated.length) {
        for (let i = updated.length; i < count; i++) {
          updated.push({ name: '', age: 25, gender: 'male' });
        }
      } else if (count < updated.length) {
        return updated.slice(0, count);
      }
      return updated;
    });
  };

  const handlePassengerChange = (index: number, field: keyof Passenger, value: any) => {
    setPassengers((prev) => {
      const updated = [...prev];
      updated[index] = { ...updated[index], [field]: value };
      return updated;
    });
  };

  const handleSubmitBooking = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!rideId || !ride) return;

    // Validate passenger fields
    for (let i = 0; i < passengers.length; i++) {
      if (!passengers[i].name.trim()) {
        setErrorMessage(`Please enter passenger ${i + 1} name.`);
        return;
      }
      if (!passengers[i].age || passengers[i].age <= 0) {
        setErrorMessage(`Please enter valid age for passenger ${i + 1}.`);
        return;
      }
    }

    try {
      setSubmitting(true);
      setErrorMessage(null);

      const res = await api.createBooking({
        ride_id: rideId,
        seats_booked: selectedSeats,
        payment_mode: paymentMode,
        passengers,
      });

      setBookingSuccess(res.booking_id || 'Booking Confirmed');
      setTimeout(() => {
        navigate('/my-rides');
      }, 2500);
    } catch (err: any) {
      setErrorMessage(err.message || 'Failed to complete booking.');
    } finally {
      setSubmitting(false);
    }
  };

  if (loading) {
    return (
      <div style={{ textAlign: 'center', padding: '5rem 0', color: 'var(--grey)' }}>
        Loading booking details...
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

  const totalPrice = selectedSeats * (ride.price_per_seat || 0);

  return (
    <div className="animate-fade-in" style={{ padding: '2rem 0' }}>
      <div className="app-container" style={{ maxWidth: 640 }}>
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
          Back to Ride
        </button>

        {bookingSuccess ? (
          <div
            className="card"
            style={{
              textAlign: 'center',
              padding: '3rem 2rem',
              background: '#ffffff',
              border: '1.5px solid var(--grey-border)',
            }}
          >
            <CheckCircle size={60} color="var(--green)" style={{ margin: '0 auto 1.25rem' }} />
            <h2 style={{ fontSize: '1.5rem', fontWeight: 800, color: 'var(--navy)', marginBottom: '0.5rem' }}>
              Booking Confirmed!
            </h2>
            <p style={{ color: 'var(--grey)', fontSize: '0.95rem', marginBottom: '1.5rem' }}>
              Your seats have been reserved. The driver has been notified of your booking.
            </p>
            <span className="badge badge-green" style={{ fontSize: '0.9rem', padding: '0.4rem 1rem' }}>
              Booking ID: {bookingSuccess}
            </span>
          </div>
        ) : (
          <div
            className="card"
            style={{
              padding: '2rem',
              background: '#ffffff',
              border: '1.5px solid var(--grey-border)',
              boxShadow: 'var(--shadow-md)',
            }}
          >
            <div style={{ marginBottom: '1.5rem' }}>
              <h1 style={{ fontSize: '1.4rem', fontWeight: 800, color: 'var(--navy)', marginBottom: '0.25rem' }}>
                Book Your Seats
              </h1>
              <p style={{ color: 'var(--grey)', fontSize: '0.9rem' }}>
                {ride.origin} → {ride.destination}
              </p>
            </div>

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

            <form onSubmit={handleSubmitBooking}>
              {/* Seats Selector */}
              <div className="form-group" style={{ marginBottom: '1.5rem' }}>
                <label className="form-label">
                  Number of Seats (Available: {ride.available_seats})
                </label>
                <div style={{ display: 'flex', gap: '0.5rem' }}>
                  {[...Array(Math.min(ride.available_seats, 6))].map((_, i) => {
                    const count = i + 1;
                    return (
                      <button
                        key={count}
                        type="button"
                        onClick={() => handleSeatChange(count)}
                        className={`btn ${selectedSeats === count ? 'btn-primary' : 'btn-outline'}`}
                        style={{ flex: 1, padding: '0.65rem' }}
                      >
                        {count} {count === 1 ? 'Seat' : 'Seats'}
                      </button>
                    );
                  })}
                </div>
              </div>

              {/* Dynamic Passenger Forms */}
              <div style={{ marginBottom: '1.5rem' }}>
                <h3 style={{ fontSize: '1rem', fontWeight: 700, color: 'var(--navy)', marginBottom: '0.75rem' }}>
                  Passenger Details
                </h3>

                <div style={{ display: 'flex', flexDirection: 'column', gap: '1rem' }}>
                  {passengers.map((p, idx) => (
                    <div
                      key={idx}
                      style={{
                        background: 'var(--bg)',
                        padding: '1rem',
                        borderRadius: 'var(--radius-md)',
                        border: '1px solid var(--grey-border)',
                      }}
                    >
                      <span style={{ fontSize: '0.8rem', fontWeight: 700, color: 'var(--navy)' }}>
                        Passenger {idx + 1}
                      </span>
                      <div style={{ display: 'grid', gridTemplateColumns: '2fr 1fr 1fr', gap: '0.75rem', marginTop: '0.5rem' }}>
                        <input
                          type="text"
                          placeholder="Full Name"
                          value={p.name}
                          onChange={(e) => handlePassengerChange(idx, 'name', e.target.value)}
                          className="input-field"
                          required
                        />
                        <input
                          type="number"
                          placeholder="Age"
                          value={p.age}
                          min={1}
                          max={120}
                          onChange={(e) => handlePassengerChange(idx, 'age', Number(e.target.value))}
                          className="input-field"
                          required
                        />
                        <select
                          value={p.gender}
                          onChange={(e) => handlePassengerChange(idx, 'gender', e.target.value)}
                          className="input-field"
                        >
                          <option value="male">Male</option>
                          <option value="female">Female</option>
                          <option value="other">Other</option>
                        </select>
                      </div>
                    </div>
                  ))}
                </div>
              </div>

              {/* Payment Mode Selector */}
              <div className="form-group" style={{ marginBottom: '1.5rem' }}>
                <label className="form-label">Payment Mode</label>
                <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '0.75rem' }}>
                  <button
                    type="button"
                    onClick={() => setPaymentMode('cash')}
                    className={`btn ${paymentMode === 'cash' ? 'btn-primary' : 'btn-outline'}`}
                    style={{ padding: '0.75rem', justifyContent: 'flex-start' }}
                  >
                    <Banknote size={18} />
                    Cash on Boarding
                  </button>
                  <button
                    type="button"
                    onClick={() => setPaymentMode('upi')}
                    className={`btn ${paymentMode === 'upi' ? 'btn-primary' : 'btn-outline'}`}
                    style={{ padding: '0.75rem', justifyContent: 'flex-start' }}
                  >
                    <CreditCard size={18} />
                    UPI / Online
                  </button>
                </div>
              </div>

              {/* Price Breakdown */}
              <div
                style={{
                  background: 'var(--bg-header)',
                  padding: '1.25rem',
                  borderRadius: 'var(--radius-lg)',
                  border: '1px solid rgba(11, 79, 216, 0.15)',
                  marginBottom: '1.5rem',
                }}
              >
                <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '0.5rem', fontSize: '0.9rem', color: 'var(--grey)' }}>
                  <span>Price per seat</span>
                  <span>₹{ride.price_per_seat}</span>
                </div>
                <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '0.75rem', fontSize: '0.9rem', color: 'var(--grey)' }}>
                  <span>Seats selected</span>
                  <span>× {selectedSeats}</span>
                </div>
                <div
                  style={{
                    display: 'flex',
                    justifyContent: 'space-between',
                    paddingTop: '0.75rem',
                    borderTop: '1px solid rgba(11, 79, 216, 0.2)',
                    fontWeight: 800,
                    fontSize: '1.25rem',
                    color: 'var(--navy)',
                  }}
                >
                  <span>Total Amount</span>
                  <span style={{ color: 'var(--blue)' }}>₹{totalPrice}</span>
                </div>
              </div>

              <button
                type="submit"
                className="btn btn-primary"
                style={{ width: '100%', padding: '0.85rem', fontSize: '1rem' }}
                disabled={submitting}
              >
                {submitting ? 'Confirming Booking...' : `Confirm & Book (${selectedSeats} Seat)`}
              </button>
            </form>
          </div>
        )}
      </div>
    </div>
  );
};
