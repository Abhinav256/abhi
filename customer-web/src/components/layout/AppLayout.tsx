import React, { useState, useEffect } from 'react';
import { Outlet } from 'react-router-dom';
import { Navbar } from './Navbar';
import { MobileBottomNav } from './MobileBottomNav';
import { useAuth } from '../../context/AuthContext';
import { api } from '../../services/api';
import { RatingModal } from '../rides/RatingModal';
import type { RatingParticipant } from '../../types';

export const AppLayout: React.FC = () => {
  const { isAuthenticated } = useAuth();
  const [pendingRating, setPendingRating] = useState<{
    rideId: string;
    participants: RatingParticipant[];
  } | null>(null);

  useEffect(() => {
    if (!isAuthenticated) return;

    const checkRating = async () => {
      try {
        const res = await api.getPendingRating();
        if (res.has_pending_rating && res.ride_id && res.participants) {
          const unrated = res.participants.filter((p) => !p.already_rated);
          if (unrated.length > 0) {
            setPendingRating({
              rideId: res.ride_id,
              participants: res.participants,
            });
          }
        }
      } catch {
        // silently ignore
      }
    };

    checkRating();
  }, [isAuthenticated]);

  return (
    <div style={{ minHeight: '100vh', display: 'flex', flexDirection: 'column' }}>
      <Navbar />

      <main className="main-content" style={{ flex: 1, paddingBottom: '3rem' }}>
        <Outlet />
      </main>

      <MobileBottomNav />

      {pendingRating && (
        <RatingModal
          isOpen={true}
          onClose={() => setPendingRating(null)}
          rideId={pendingRating.rideId}
          participants={pendingRating.participants}
          onSuccess={() => setPendingRating(null)}
        />
      )}
    </div>
  );
};
