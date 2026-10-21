import React, { useState } from 'react';
import { Star, CheckCircle } from 'lucide-react';
import { Modal } from '../ui/Modal';
import type { RatingParticipant } from '../../types';
import { api } from '../../services/api';

interface RatingModalProps {
  isOpen: boolean;
  onClose: () => void;
  rideId: string;
  participants: RatingParticipant[];
  onSuccess: () => void;
}

export const RatingModal: React.FC<RatingModalProps> = ({
  isOpen,
  onClose,
  rideId,
  participants,
  onSuccess,
}) => {
  const [ratings, setRatings] = useState<Record<string, number>>({});
  const [feedbacks, setFeedbacks] = useState<Record<string, string>>({});
  const [submitting, setSubmitting] = useState(false);
  const [submitted, setSubmitted] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const handleStarClick = (userId: string, score: number) => {
    setRatings((prev) => ({ ...prev, [userId]: score }));
  };

  const handleFeedbackChange = (userId: string, text: string) => {
    setFeedbacks((prev) => ({ ...prev, [userId]: text }));
  };

  const handleSubmit = async () => {
    const payloadRatings = participants
      .filter((p) => !p.already_rated)
      .map((p) => ({
        ratee_id: p.user_id,
        role: p.role,
        rating: ratings[p.user_id] || 5,
        feedback: feedbacks[p.user_id] || '',
      }));

    if (payloadRatings.length === 0) {
      onClose();
      return;
    }

    try {
      setSubmitting(true);
      setError(null);
      await api.submitRatings({
        ride_id: rideId,
        ratings: payloadRatings,
      });
      setSubmitted(true);
      setTimeout(() => {
        onSuccess();
        onClose();
      }, 1500);
    } catch (err: any) {
      setError(err.message || 'Failed to submit ratings.');
    } finally {
      setSubmitting(false);
    }
  };

  const unratedParticipants = participants.filter((p) => !p.already_rated);

  return (
    <Modal isOpen={isOpen} onClose={onClose} title="How was your journey?">
      {submitted ? (
        <div style={{ textAlign: 'center', padding: '2rem 1rem' }}>
          <CheckCircle size={48} color="var(--green)" style={{ margin: '0 auto 1rem' }} />
          <h3 style={{ fontSize: '1.25rem', fontWeight: 700, color: 'var(--navy)' }}>Thank you!</h3>
          <p style={{ color: 'var(--grey)', marginTop: '0.5rem' }}>Your feedback helps keep AbhiShare safe and friendly.</p>
        </div>
      ) : (
        <div style={{ display: 'flex', flexDirection: 'column', gap: '1.5rem' }}>
          <p style={{ color: 'var(--grey)', fontSize: '0.9rem' }}>
            Please rate your co-travelers to build a trusted community.
          </p>

          {error && (
            <div
              style={{
                background: 'var(--red-bg)',
                color: 'var(--red)',
                padding: '0.75rem',
                borderRadius: 'var(--radius-md)',
                fontSize: '0.875rem',
              }}
            >
              {error}
            </div>
          )}

          {unratedParticipants.map((participant) => {
            const currentScore = ratings[participant.user_id] || 5;
            return (
              <div
                key={participant.user_id}
                style={{
                  background: 'var(--bg)',
                  padding: '1rem',
                  borderRadius: 'var(--radius-lg)',
                  border: '1px solid var(--grey-border)',
                }}
              >
                <div style={{ display: 'flex', alignItems: 'center', gap: '0.75rem', marginBottom: '0.75rem' }}>
                  <div
                    style={{
                      width: 40,
                      height: 40,
                      borderRadius: '50%',
                      background: 'var(--blue)',
                      color: '#ffffff',
                      display: 'flex',
                      alignItems: 'center',
                      justifyContent: 'center',
                      fontWeight: 700,
                    }}
                  >
                    {participant.name.charAt(0).toUpperCase()}
                  </div>
                  <div>
                    <h4 style={{ fontWeight: 600, color: 'var(--navy)' }}>{participant.name}</h4>
                    <span style={{ fontSize: '0.75rem', color: 'var(--grey)', textTransform: 'capitalize' }}>
                      {participant.role}
                    </span>
                  </div>
                </div>

                {/* Stars */}
                <div style={{ display: 'flex', gap: '0.5rem', marginBottom: '0.75rem' }}>
                  {[1, 2, 3, 4, 5].map((star) => (
                    <button
                      key={star}
                      type="button"
                      onClick={() => handleStarClick(participant.user_id, star)}
                      style={{ cursor: 'pointer', padding: '2px' }}
                    >
                      <Star
                        size={28}
                        fill={star <= currentScore ? 'var(--amber)' : 'none'}
                        color={star <= currentScore ? 'var(--amber)' : 'var(--grey-light)'}
                      />
                    </button>
                  ))}
                </div>

                {/* Feedback Input */}
                <input
                  type="text"
                  placeholder="Leave a short comment (optional)"
                  value={feedbacks[participant.user_id] || ''}
                  onChange={(e) => handleFeedbackChange(participant.user_id, e.target.value)}
                  className="input-field"
                  style={{ fontSize: '0.85rem' }}
                />
              </div>
            );
          })}

          <div style={{ display: 'flex', justifyContent: 'flex-end', gap: '0.75rem', marginTop: '0.5rem' }}>
            <button type="button" onClick={onClose} className="btn btn-outline" disabled={submitting}>
              Skip
            </button>
            <button
              type="button"
              onClick={handleSubmit}
              className="btn btn-primary"
              disabled={submitting}
            >
              {submitting ? 'Submitting...' : 'Submit Rating'}
            </button>
          </div>
        </div>
      )}
    </Modal>
  );
};
