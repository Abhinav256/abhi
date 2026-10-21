import React, { useState } from 'react';
import { useSearchParams, useNavigate } from 'react-router-dom';
import { Lock, ArrowRight, AlertCircle, KeyRound } from 'lucide-react';
import { api } from '../../services/api';
import { useAuth } from '../../context/AuthContext';

export const PasscodeLoginPage: React.FC = () => {
  const [searchParams] = useSearchParams();
  const navigate = useNavigate();
  const { login } = useAuth();

  const identifier = searchParams.get('identifier') || '';

  const [pin, setPin] = useState('');
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const handleLogin = async (e: React.FormEvent) => {
    e.preventDefault();
    if (pin.length !== 4) {
      setError('Please enter your 4-digit PIN.');
      return;
    }

    try {
      setLoading(true);
      setError(null);

      const res = await api.loginWithPasscode(identifier, pin);
      login(res.token, res.user);
      navigate('/');
    } catch (err: any) {
      setError(err.message || 'Incorrect PIN. Please try again.');
    } finally {
      setLoading(false);
    }
  };

  const handleLoginWithOTP = async () => {
    try {
      await api.sendOTPUniversal(identifier);
      navigate(`/login/otp?identifier=${encodeURIComponent(identifier)}`);
    } catch (err: any) {
      setError(err.message || 'Failed to send OTP.');
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
            <Lock size={28} />
          </div>
          <h1 style={{ fontSize: '1.6rem', fontWeight: 800, color: 'var(--navy)' }}>
            Enter Passcode
          </h1>
          <p style={{ color: 'var(--grey)', fontSize: '0.9rem', marginTop: '0.25rem' }}>
            Enter your 4-digit security PIN for <br />
            <strong>{identifier}</strong>
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

        <form onSubmit={handleLogin}>
          <div className="form-group" style={{ marginBottom: '1.5rem' }}>
            <label className="form-label" style={{ textAlign: 'center' }}>
              4-Digit PIN
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

          <button
            type="submit"
            className="btn btn-primary"
            style={{ width: '100%', padding: '0.85rem', fontSize: '1rem' }}
            disabled={loading || pin.length !== 4}
          >
            {loading ? 'Authenticating...' : 'Sign In'}
            <ArrowRight size={18} />
          </button>
        </form>

        <div style={{ textAlign: 'center', marginTop: '1.75rem' }}>
          <button
            type="button"
            onClick={handleLoginWithOTP}
            style={{
              color: 'var(--blue)',
              fontWeight: 600,
              fontSize: '0.875rem',
              display: 'inline-flex',
              alignItems: 'center',
              gap: '0.35rem',
              cursor: 'pointer',
            }}
          >
            <KeyRound size={15} /> Log in via One-Time Password (OTP)
          </button>
        </div>
      </div>
    </div>
  );
};
