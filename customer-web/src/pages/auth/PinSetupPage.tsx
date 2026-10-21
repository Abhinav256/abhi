import React, { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { KeyRound, ArrowRight, AlertCircle } from 'lucide-react';
import { api } from '../../services/api';
import { useAuth } from '../../context/AuthContext';

export const PinSetupPage: React.FC = () => {
  const navigate = useNavigate();
  const { refreshUser } = useAuth();

  const [pin, setPin] = useState('');
  const [confirmPin, setConfirmPin] = useState('');
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const handleSavePin = async (e: React.FormEvent) => {
    e.preventDefault();
    if (pin.length !== 4) {
      setError('PIN must be exactly 4 digits.');
      return;
    }
    if (pin !== confirmPin) {
      setError('PIN and Confirm PIN do not match.');
      return;
    }

    try {
      setLoading(true);
      setError(null);
      await api.setPIN(pin);
      await refreshUser();
      navigate('/');
    } catch (err: any) {
      setError(err.message || 'Failed to set security PIN.');
    } finally {
      setLoading(false);
    }
  };

  return (
    <div
      className="animate-fade-in"
      style={{
        minHeight: '100vh',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        background: 'linear-gradient(135deg, #0B1B3B 0%, #102A6B 100%)',
        padding: '1.5rem',
      }}
    >
      <div
        className="card"
        style={{
          width: '100%',
          maxWidth: 440,
          background: '#ffffff',
          borderRadius: 'var(--radius-2xl)',
          padding: '2.5rem 2rem',
          boxShadow: 'var(--shadow-lg)',
        }}
      >
        <div style={{ textAlign: 'center', marginBottom: '2rem' }}>
          <div
            style={{
              width: 52,
              height: 52,
              borderRadius: 'var(--radius-xl)',
              background: 'var(--bg-header)',
              color: 'var(--blue)',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              margin: '0 auto 1rem',
            }}
          >
            <KeyRound size={28} />
          </div>
          <h1 style={{ fontSize: '1.6rem', fontWeight: 800, color: 'var(--navy)' }}>
            Set Security PIN
          </h1>
          <p style={{ color: 'var(--grey)', fontSize: '0.9rem', marginTop: '0.25rem' }}>
            Choose a 4-digit passcode for quick and secure logins.
          </p>
        </div>

        {error && (
          <div
            style={{
              background: 'var(--red-bg)',
              color: 'var(--red)',
              padding: '0.75rem 1rem',
              borderRadius: 'var(--radius-md)',
              marginBottom: '1.25rem',
              fontSize: '0.85rem',
              display: 'flex',
              alignItems: 'center',
              gap: '0.5rem',
            }}
          >
            <AlertCircle size={16} />
            <span>{error}</span>
          </div>
        )}

        <form onSubmit={handleSavePin}>
          <div className="form-group" style={{ marginBottom: '1.25rem' }}>
            <label className="form-label" style={{ textAlign: 'center' }}>
              Choose 4-Digit PIN
            </label>
            <input
              type="password"
              maxLength={4}
              placeholder="• • • •"
              value={pin}
              onChange={(e) => setPin(e.target.value.replace(/\D/g, ''))}
              className="input-field"
              style={{
                textAlign: 'center',
                letterSpacing: '12px',
                fontSize: '1.75rem',
                fontWeight: 700,
              }}
              required
              autoFocus
            />
          </div>

          <div className="form-group" style={{ marginBottom: '1.75rem' }}>
            <label className="form-label" style={{ textAlign: 'center' }}>
              Confirm 4-Digit PIN
            </label>
            <input
              type="password"
              maxLength={4}
              placeholder="• • • •"
              value={confirmPin}
              onChange={(e) => setConfirmPin(e.target.value.replace(/\D/g, ''))}
              className="input-field"
              style={{
                textAlign: 'center',
                letterSpacing: '12px',
                fontSize: '1.75rem',
                fontWeight: 700,
              }}
              required
            />
          </div>

          <button
            type="submit"
            className="btn btn-primary"
            style={{ width: '100%', padding: '0.85rem', fontSize: '1rem' }}
            disabled={loading || pin.length !== 4 || confirmPin.length !== 4}
          >
            {loading ? 'Saving PIN...' : 'Save & Continue'}
            <ArrowRight size={18} />
          </button>
        </form>
      </div>
    </div>
  );
};
