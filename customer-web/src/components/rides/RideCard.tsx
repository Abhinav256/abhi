import React from 'react';
import { useNavigate } from 'react-router-dom';
import {
  Clock,
  Star,
  Users,
  Car,
  ChevronRight,
  ShieldCheck,
} from 'lucide-react';
import type { Ride } from '../../types';

interface RideCardProps {
  ride: Ride;
}

export const RideCard: React.FC<RideCardProps> = ({ ride }) => {
  const navigate = useNavigate();

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
      return d.toLocaleDateString('en-IN', { day: 'numeric', month: 'short' });
    } catch {
      return dateStr;
    }
  };

  const getVehicleTypeLabel = (type?: string) => {
    switch (type) {
      case 'two_wheeler':
        return '2-Seater';
      case 'five_seater':
        return '5-Seater';
      case 'seven_seater':
        return '7-Seater';
      default:
        return type || 'Car';
    }
  };

  const driverName =
    ride.driver_name ||
    ride.driver?.full_name ||
    'Verified Driver';

  const driverRating =
    ride.driver_rating ||
    ride.driver?.average_rating ||
    '5.0';

  const driverPhoto =
    ride.driver_photo ||
    ride.driver?.driver_selfie_url ||
    ride.driver?.profile_photo;

  return (
    <div
      className="card card-hover"
      style={{
        display: 'flex',
        flexDirection: 'column',
        gap: '1rem',
        cursor: 'pointer',
        border: '1.5px solid var(--grey-border)',
      }}
      onClick={() => navigate(`/rides/${ride.id}`)}
    >
      {/* Top Row: Time, Date & Price */}
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: '0.6rem' }}>
          <div
            style={{
              padding: '0.35rem 0.65rem',
              borderRadius: 'var(--radius-md)',
              background: 'var(--bg-header)',
              color: 'var(--blue)',
              fontWeight: 700,
              fontSize: '1rem',
              display: 'flex',
              alignItems: 'center',
              gap: '0.35rem',
            }}
          >
            <Clock size={16} />
            <span>{formatTime(ride.departure_time)}</span>
          </div>
          <span style={{ fontSize: '0.85rem', color: 'var(--grey)', fontWeight: 500 }}>
            {formatDate(ride.journey_date)}
          </span>
        </div>

        <div style={{ textAlign: 'right' }}>
          <div style={{ fontSize: '1.35rem', fontWeight: 800, color: 'var(--blue)' }}>
            ₹{ride.price_per_seat}
          </div>
          <span style={{ fontSize: '0.75rem', color: 'var(--grey)' }}>per seat</span>
        </div>
      </div>

      {/* Middle Row: Route (Origin -> Destination) */}
      <div style={{ display: 'flex', flexDirection: 'column', gap: '0.5rem', position: 'relative' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: '0.75rem' }}>
          <div
            style={{
              width: 10,
              height: 10,
              borderRadius: '50%',
              background: 'var(--green)',
              flexShrink: 0,
            }}
          />
          <span
            style={{
              fontWeight: 600,
              color: 'var(--navy)',
              fontSize: '0.95rem',
              whiteSpace: 'nowrap',
              overflow: 'hidden',
              textOverflow: 'ellipsis',
            }}
          >
            {ride.origin}
          </span>
        </div>

        {/* Route Line */}
        <div
          style={{
            position: 'absolute',
            left: 4,
            top: 12,
            bottom: 12,
            width: 2,
            background: 'var(--grey-border)',
          }}
        />

        <div style={{ display: 'flex', alignItems: 'center', gap: '0.75rem' }}>
          <div
            style={{
              width: 10,
              height: 10,
              borderRadius: '50%',
              background: 'var(--blue)',
              flexShrink: 0,
            }}
          />
          <span
            style={{
              fontWeight: 600,
              color: 'var(--navy)',
              fontSize: '0.95rem',
              whiteSpace: 'nowrap',
              overflow: 'hidden',
              textOverflow: 'ellipsis',
            }}
          >
            {ride.destination}
          </span>
        </div>
      </div>

      {/* Divider */}
      <div style={{ height: 1, background: 'var(--grey-border)', margin: '0.2rem 0' }} />

      {/* Bottom Row: Driver info & Vehicle badge */}
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', flexWrap: 'wrap', gap: '0.5rem' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: '0.6rem' }}>
          {driverPhoto ? (
            <img
              src={driverPhoto}
              alt={driverName}
              style={{ width: 34, height: 34, borderRadius: '50%', objectFit: 'cover' }}
            />
          ) : (
            <div
              style={{
                width: 34,
                height: 34,
                borderRadius: '50%',
                background: 'var(--bg-header)',
                color: 'var(--blue)',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                fontWeight: 700,
                fontSize: '0.85rem',
              }}
            >
              {driverName.charAt(0)}
            </div>
          )}

          <div>
            <div style={{ display: 'flex', alignItems: 'center', gap: '0.35rem' }}>
              <span style={{ fontWeight: 600, fontSize: '0.875rem', color: 'var(--navy)' }}>
                {driverName}
              </span>
              <ShieldCheck size={14} color="var(--green)" />
            </div>
            <div style={{ display: 'flex', alignItems: 'center', gap: '0.25rem', fontSize: '0.75rem', color: 'var(--amber-text)' }}>
              <Star size={12} fill="var(--amber)" color="var(--amber)" />
              <span style={{ fontWeight: 600 }}>{driverRating}</span>
            </div>
          </div>
        </div>

        <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
          {/* Vehicle Type / Seater Badge */}
          <span className="badge badge-grey" style={{ display: 'flex', alignItems: 'center', gap: '0.25rem' }}>
            <Car size={13} />
            <span>{getVehicleTypeLabel(ride.vehicle_type || ride.vehicle?.vehicle_type)}</span>
          </span>

          {/* Seats left Badge */}
          <span
            className={`badge ${ride.available_seats > 1 ? 'badge-green' : 'badge-amber'}`}
            style={{ display: 'flex', alignItems: 'center', gap: '0.25rem' }}
          >
            <Users size={13} />
            <span>{ride.available_seats} left</span>
          </span>

          <ChevronRight size={18} color="var(--grey)" />
        </div>
      </div>
    </div>
  );
};
