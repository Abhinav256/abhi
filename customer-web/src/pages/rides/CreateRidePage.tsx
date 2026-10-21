import React, { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import {
  Car,
  Plus,
  ArrowUpDown,
  Camera,
  CheckCircle,
  AlertCircle,
  ShieldCheck,
} from 'lucide-react';
import { api } from '../../services/api';
import type { Vehicle } from '../../types';
import { compressImage } from '../../services/imageCompression';

export const CreateRidePage: React.FC = () => {
  const navigate = useNavigate();

  const [vehicles, setVehicles] = useState<Vehicle[]>([]);
  const [loadingVehicles, setLoadingVehicles] = useState(true);

  // Form State
  const [selectedVehicleId, setSelectedVehicleId] = useState<string>('');
  const [origin, setOrigin] = useState('');
  const [destination, setDestination] = useState('');
  const [journeyDate, setJourneyDate] = useState(() => {
    return new Date().toISOString().split('T')[0];
  });
  const [departureTime, setDepartureTime] = useState('09:00');
  const [availableSeats, setAvailableSeats] = useState<number>(1);
  const [pricePerSeat, setPricePerSeat] = useState<number>(150);
  const [instantBooking, setInstantBooking] = useState(true);
  const [notes, setNotes] = useState('');

  // Multi-step
  const [currentStep, setCurrentStep] = useState<1 | 2>(1);
  const [createdRideId, setCreatedRideId] = useState<string | null>(null);

  // Step 2: Selfie state
  const [selfieFile, setSelfieFile] = useState<File | null>(null);
  const [selfiePreview, setSelfiePreview] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const [success, setSuccess] = useState(false);

  useEffect(() => {
    const fetchVehicles = async () => {
      try {
        setLoadingVehicles(true);
        const list = await api.getVehicles();
        setVehicles(list);
        if (list.length > 0) {
          setSelectedVehicleId(list[0].id);
          const max = getMaxSeats(list[0]);
          setAvailableSeats(Math.min(3, max));
        }
      } catch (err: any) {
        setErrorMessage(err.message || 'Failed to load vehicles');
      } finally {
        setLoadingVehicles(false);
      }
    };

    fetchVehicles();
  }, []);

  const getMaxSeats = (v: Vehicle): number => {
    switch (v.vehicle_type) {
      case 'two_wheeler':
        return 1;
      case 'five_seater':
        return 4;
      case 'seven_seater':
        return 6;
      default:
        return 4;
    }
  };

  const handleVehicleChange = (vehicleId: string) => {
    setSelectedVehicleId(vehicleId);
    const vehicle = vehicles.find((v) => v.id === vehicleId);
    if (vehicle) {
      const max = getMaxSeats(vehicle);
      if (availableSeats > max) {
        setAvailableSeats(max);
      }
    }
  };

  const handleSwap = () => {
    const temp = origin;
    setOrigin(destination);
    setDestination(temp);
  };

  const handleCreateDraft = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!origin.trim() || !destination.trim()) {
      setErrorMessage('Please enter both pickup origin and destination.');
      return;
    }
    if (!selectedVehicleId) {
      setErrorMessage('Please select a vehicle.');
      return;
    }

    try {
      setSubmitting(true);
      setErrorMessage(null);

      const res = await api.createRide({
        vehicle_id: selectedVehicleId,
        origin: origin.trim(),
        destination: destination.trim(),
        journey_date: journeyDate,
        departure_time: `${departureTime}:00`,
        available_seats: availableSeats,
        price_per_seat: pricePerSeat,
        instant_booking: instantBooking,
        notes: notes.trim(),
      });

      const rideId = res.ride_id || res.ride?.id;
      if (!rideId) {
        throw new Error('Server did not return a valid ride ID.');
      }

      setCreatedRideId(rideId);
      setCurrentStep(2);
    } catch (err: any) {
      setErrorMessage(err.message || 'Failed to create ride draft.');
    } finally {
      setSubmitting(false);
    }
  };

  const handleSelfieSelect = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;

    try {
      const res = await compressImage(file, 'selfie');
      setSelfieFile(res.file);
      setSelfiePreview(res.previewUrl);
    } catch {
      setSelfieFile(file);
      setSelfiePreview(URL.createObjectURL(file));
    }
  };

  const handlePublishRide = async () => {
    if (!createdRideId) return;
    if (!selfieFile) {
      setErrorMessage('Please upload or take a driver verification selfie.');
      return;
    }

    try {
      setSubmitting(true);
      setErrorMessage(null);

      // 1. Upload compressed selfie
      await api.uploadRideSelfie(createdRideId, selfieFile);

      // 2. Publish ride
      await api.publishRide(createdRideId);

      setSuccess(true);
      setTimeout(() => {
        navigate('/my-rides');
      }, 2000);
    } catch (err: any) {
      setErrorMessage(err.message || 'Failed to publish ride.');
    } finally {
      setSubmitting(false);
    }
  };

  const selectedVehicle = vehicles.find((v) => v.id === selectedVehicleId);
  const maxAllowedSeats = selectedVehicle ? getMaxSeats(selectedVehicle) : 4;

  if (loadingVehicles) {
    return (
      <div style={{ textAlign: 'center', padding: '5rem 0', color: 'var(--grey)' }}>
        Loading vehicle details...
      </div>
    );
  }

  // User requirement: If there are no vehicles, say "Add vehicle" and redirect to My Vehicles screen!
  if (vehicles.length === 0) {
    return (
      <div className="animate-fade-in" style={{ padding: '3rem 0' }}>
        <div className="app-container" style={{ maxWidth: 540 }}>
          <div
            className="card"
            style={{
              textAlign: 'center',
              padding: '3rem 2rem',
              border: '1.5px solid var(--grey-border)',
            }}
          >
            <div
              style={{
                width: 64,
                height: 64,
                borderRadius: '50%',
                background: 'var(--bg-header)',
                color: 'var(--blue)',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                margin: '0 auto 1.25rem',
              }}
            >
              <Car size={34} />
            </div>
            <h2 style={{ fontSize: '1.4rem', fontWeight: 800, color: 'var(--navy)', marginBottom: '0.5rem' }}>
              No vehicles available
            </h2>
            <p style={{ color: 'var(--grey)', fontSize: '0.95rem', marginBottom: '2rem' }}>
              Add a vehicle before creating a ride. Once registered, you will be able to offer empty seats to passengers.
            </p>
            <button
              type="button"
              className="btn btn-primary"
              onClick={() => navigate('/vehicles')}
              style={{ width: '100%', padding: '0.85rem' }}
            >
              <Plus size={18} />
              Add Vehicle
            </button>
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className="animate-fade-in" style={{ padding: '2rem 0' }}>
      <div className="app-container" style={{ maxWidth: 680 }}>
        {/* Stepper Indicator */}
        <div
          style={{
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            gap: '1rem',
            marginBottom: '2rem',
          }}
        >
          <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
            <div
              style={{
                width: 32,
                height: 32,
                borderRadius: '50%',
                background: currentStep >= 1 ? 'var(--blue)' : 'var(--grey-border)',
                color: '#ffffff',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                fontWeight: 700,
                fontSize: '0.85rem',
              }}
            >
              1
            </div>
            <span style={{ fontWeight: 600, color: currentStep >= 1 ? 'var(--navy)' : 'var(--grey)' }}>
              Ride Details
            </span>
          </div>

          <div style={{ width: 40, height: 2, background: currentStep >= 2 ? 'var(--blue)' : 'var(--grey-border)' }} />

          <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
            <div
              style={{
                width: 32,
                height: 32,
                borderRadius: '50%',
                background: currentStep >= 2 ? 'var(--blue)' : 'var(--grey-border)',
                color: '#ffffff',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                fontWeight: 700,
                fontSize: '0.85rem',
              }}
            >
              2
            </div>
            <span style={{ fontWeight: 600, color: currentStep >= 2 ? 'var(--navy)' : 'var(--grey)' }}>
              Driver Selfie
            </span>
          </div>
        </div>

        {/* Error message */}
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

        {/* Step 1: Ride Details */}
        {currentStep === 1 && (
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
              <h2 style={{ fontSize: '1.4rem', fontWeight: 800, color: 'var(--navy)' }}>
                Offer a Ride
              </h2>
              <p style={{ color: 'var(--grey)', fontSize: '0.9rem' }}>
                Fill in your route details and select your registered vehicle.
              </p>
            </div>

            <form onSubmit={handleCreateDraft}>
              {/* Vehicle Selector */}
              <div className="form-group">
                <label className="form-label">Select Vehicle</label>
                <select
                  value={selectedVehicleId}
                  onChange={(e) => handleVehicleChange(e.target.value)}
                  className="input-field"
                >
                  {vehicles.map((v) => (
                    <option key={v.id} value={v.id}>
                      {v.model} • {v.vehicle_number} ({v.vehicle_type === 'two_wheeler' ? '2-Seater' : v.vehicle_type === 'seven_seater' ? '7-Seater' : '5-Seater'})
                    </option>
                  ))}
                </select>
              </div>

              {/* Pickup & Destination */}
              <div style={{ position: 'relative', marginBottom: '1rem' }}>
                <div className="form-group">
                  <label className="form-label">Pickup Location</label>
                  <input
                    type="text"
                    placeholder="e.g. Madhapur, Hitec City"
                    value={origin}
                    onChange={(e) => setOrigin(e.target.value)}
                    className="input-field"
                    required
                  />
                </div>

                {/* Swap button */}
                <div
                  style={{
                    position: 'absolute',
                    right: 12,
                    top: '50%',
                    transform: 'translateY(-50%)',
                    zIndex: 2,
                  }}
                >
                  <button
                    type="button"
                    onClick={handleSwap}
                    style={{
                      width: 36,
                      height: 36,
                      borderRadius: '50%',
                      background: 'var(--bg-header)',
                      border: '1px solid var(--grey-border)',
                      display: 'flex',
                      alignItems: 'center',
                      justifyContent: 'center',
                      color: 'var(--blue)',
                      cursor: 'pointer',
                    }}
                    title="Swap"
                  >
                    <ArrowUpDown size={16} />
                  </button>
                </div>

                <div className="form-group" style={{ margin: 0 }}>
                  <label className="form-label">Drop Destination</label>
                  <input
                    type="text"
                    placeholder="e.g. Airport, Financial District"
                    value={destination}
                    onChange={(e) => setDestination(e.target.value)}
                    className="input-field"
                    required
                  />
                </div>
              </div>

              {/* Date & Time Grid */}
              <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '1rem', marginBottom: '1rem' }}>
                <div className="form-group" style={{ margin: 0 }}>
                  <label className="form-label">Departure Date</label>
                  <input
                    type="date"
                    value={journeyDate}
                    onChange={(e) => setJourneyDate(e.target.value)}
                    className="input-field"
                    required
                  />
                </div>

                <div className="form-group" style={{ margin: 0 }}>
                  <label className="form-label">Departure Time</label>
                  <input
                    type="time"
                    value={departureTime}
                    onChange={(e) => setDepartureTime(e.target.value)}
                    className="input-field"
                    required
                  />
                </div>
              </div>

              {/* Seats & Price Grid */}
              <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '1rem', marginBottom: '1rem' }}>
                <div className="form-group" style={{ margin: 0 }}>
                  <label className="form-label">Seats Available (Max: {maxAllowedSeats})</label>
                  <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
                    {[...Array(maxAllowedSeats)].map((_, i) => {
                      const count = i + 1;
                      return (
                        <button
                          key={count}
                          type="button"
                          onClick={() => setAvailableSeats(count)}
                          className={`btn ${availableSeats === count ? 'btn-primary' : 'btn-outline'}`}
                          style={{
                            flex: 1,
                            padding: '0.5rem',
                            borderRadius: 'var(--radius-md)',
                            fontSize: '0.9rem',
                          }}
                        >
                          {count}
                        </button>
                      );
                    })}
                  </div>
                </div>

                <div className="form-group" style={{ margin: 0 }}>
                  <label className="form-label">Price per Seat (₹)</label>
                  <div style={{ position: 'relative' }}>
                    <input
                      type="number"
                      min={10}
                      max={10000}
                      value={pricePerSeat}
                      onChange={(e) => setPricePerSeat(Number(e.target.value))}
                      className="input-field"
                      required
                    />
                  </div>
                </div>
              </div>

              {/* Instant Booking Toggle */}
              <div
                style={{
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'space-between',
                  padding: '0.75rem 0',
                  borderTop: '1px solid var(--grey-border)',
                  borderBottom: '1px solid var(--grey-border)',
                  marginBottom: '1rem',
                }}
              >
                <div>
                  <div style={{ fontWeight: 600, color: 'var(--navy)', fontSize: '0.9rem' }}>
                    Instant Seat Booking
                  </div>
                  <div style={{ fontSize: '0.75rem', color: 'var(--grey)' }}>
                    Auto-accept passenger bookings without manual approval
                  </div>
                </div>
                <input
                  type="checkbox"
                  checked={instantBooking}
                  onChange={(e) => setInstantBooking(e.target.checked)}
                  style={{ width: 18, height: 18, accentColor: 'var(--blue)' }}
                />
              </div>

              {/* Route Notes */}
              <div className="form-group">
                <label className="form-label">Ride Guidelines / Notes (Optional)</label>
                <textarea
                  rows={2}
                  placeholder="e.g. No luggage over 10kg, AC available, please be on time"
                  value={notes}
                  onChange={(e) => setNotes(e.target.value)}
                  className="input-field"
                  style={{ resize: 'vertical' }}
                />
              </div>

              <button
                type="submit"
                className="btn btn-primary"
                style={{ width: '100%', padding: '0.85rem', marginTop: '0.5rem' }}
                disabled={submitting}
              >
                {submitting ? 'Creating Draft...' : 'Next: Verification Selfie'}
              </button>
            </form>
          </div>
        )}

        {/* Step 2: Driver Selfie Verification */}
        {currentStep === 2 && (
          <div
            className="card"
            style={{
              padding: '2rem',
              background: '#ffffff',
              border: '1.5px solid var(--grey-border)',
              boxShadow: 'var(--shadow-md)',
              textAlign: 'center',
            }}
          >
            {success ? (
              <div style={{ padding: '2rem 1rem' }}>
                <CheckCircle size={56} color="var(--green)" style={{ margin: '0 auto 1rem' }} />
                <h2 style={{ fontSize: '1.4rem', fontWeight: 800, color: 'var(--navy)' }}>
                  Ride Published Successfully!
                </h2>
                <p style={{ color: 'var(--grey)', marginTop: '0.5rem' }}>
                  Your ride is now visible in the search catalog. Redirecting to your rides...
                </p>
              </div>
            ) : (
              <div>
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
                    margin: '0 auto 1rem',
                  }}
                >
                  <ShieldCheck size={28} />
                </div>
                <h2 style={{ fontSize: '1.35rem', fontWeight: 800, color: 'var(--navy)', marginBottom: '0.4rem' }}>
                  Driver Selfie Verification
                </h2>
                <p style={{ color: 'var(--grey)', fontSize: '0.9rem', maxWidth: 440, margin: '0 auto 1.5rem' }}>
                  AbhiShare requires driver verification before publishing to guarantee passengers travel with verified members.
                </p>

                {/* Selfie Upload / Preview Area */}
                <div
                  style={{
                    width: 220,
                    height: 220,
                    borderRadius: '50%',
                    margin: '0 auto 1.5rem',
                    border: '2px dashed var(--blue)',
                    display: 'flex',
                    alignItems: 'center',
                    justifyContent: 'center',
                    position: 'relative',
                    overflow: 'hidden',
                    background: 'var(--bg)',
                  }}
                >
                  {selfiePreview ? (
                    <img
                      src={selfiePreview}
                      alt="Selfie Preview"
                      style={{ width: '100%', height: '100%', objectFit: 'cover' }}
                    />
                  ) : (
                    <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: '0.5rem' }}>
                      <Camera size={36} color="var(--blue)" />
                      <span style={{ fontSize: '0.85rem', fontWeight: 600, color: 'var(--navy)' }}>
                        Take / Upload Selfie
                      </span>
                    </div>
                  )}

                  <input
                    type="file"
                    accept="image/*"
                    capture="user"
                    onChange={handleSelfieSelect}
                    style={{
                      position: 'absolute',
                      inset: 0,
                      opacity: 0,
                      cursor: 'pointer',
                    }}
                  />
                </div>

                <div style={{ display: 'flex', gap: '1rem', justifyContent: 'center' }}>
                  <button
                    type="button"
                    onClick={() => setCurrentStep(1)}
                    className="btn btn-outline"
                    disabled={submitting}
                  >
                    Back to Details
                  </button>
                  <button
                    type="button"
                    onClick={handlePublishRide}
                    className="btn btn-primary"
                    disabled={submitting || !selfieFile}
                  >
                    {submitting ? 'Publishing Ride...' : 'Publish Ride Now'}
                  </button>
                </div>
              </div>
            )}
          </div>
        )}
      </div>
    </div>
  );
};
