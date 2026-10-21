import React, { useState, useEffect } from 'react';
import { useSearchParams, useNavigate } from 'react-router-dom';
import { ShieldCheck, ArrowRight, AlertCircle, RefreshCw } from 'lucide-react';
import { api } from '../../services/api';
import { useAuth } from '../../context/AuthContext';

export const OtpPage: React.FC = () => {
  const [searchParams] = useSearchParams();
  const navigate = useNavigate();
  const { login } = useAuth();

  const identifier = searchParams.get('identifier') || '';

  const [otp, setOtp] = useState('');
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Resend Countdown Timer
  const [countdown, setCountdown] = useState(30);

  useEffect(() => {
    if (countdown > 0) {
      const timer = setTimeout(() => setCountdown(countdown - 1), 1000);
      return () => clearTimeout(timer);
    }
  }, [countdown]);

  const handleVerify = async (e: React.FormEvent) => {
    e.preventDefault();
    if (otp.length !== 6) {
      setError('Please enter the complete 6-digit OTP.');
      return;
    }

    try {
      setLoading(true);
      setError(null);

      const res = await api.verifyOTPAndCheck(identifier, otp);

      if (res.exists && res.token && res.user) {
        login(res.token, res.user);

        // If user already has PIN setup, navigate home; else redirect to PIN setup
        if (res.user.has_pin) {
          navigate('/');
        } else {
          navigate('/pin-setup');
        }
      } else {
        // New user! Redirect to signup with pre-filled identifier
        navigate(`/signup?identifier=${encodeURIComponent(identifier)}`);
      }
    } catch (err: any) {
      setError(err.message || 'Invalid OTP code. Please try again.');
    } finally {
      setLoading(false);
    }
  };

  const handleResend = async () => {
    if (countdown > 0) return;
    try {
      setError(null);
      await api.sendOTPUniversal(identifier);
      setCountdown(30);
    } catch (err: any) {
      setError(err.message || 'Failed to resend OTP.');
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
            <ShieldCheck size={28} />
          </div>
          <h1 style={{ fontSize: '1.6rem', fontWeight: 800, color: 'var(--navy)' }}>
            Verify OTP
          </h1>
          <p style={{ color: 'var(--grey)', fontSize: '0.9rem', marginTop: '0.25rem' }}>
            Enter the 6-digit verification code sent to <br />
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

        <form onSubmit={handleVerify}>
          <div className="form-group" style={{ marginBottom: '1.5rem' }}>
            <label className="form-label" style={{ textAlign: 'center' }}>
              6-Digit Code
            </label>
            <input
              type="text"
              maxLength={6}
              placeholder="• • • • • •"
              value={otp}
              onChange={(e) => setOtp(e.target.value.replace(/\D/g, ''))}
              className="input-field"
              style={{
                textAlign: 'center',
                letterSpacing: '8px',
                fontSize: '1.5rem',
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
            disabled={loading || otp.length !== 6}
          >
            {loading ? 'Verifying...' : 'Verify & Continue'}
            <ArrowRight size={18} />
          </button>
        </form>

        <div style={{ textAlign: 'center', marginTop: '1.5rem' }}>
          {countdown > 0 ? (
            <span style={{ fontSize: '0.85rem', color: 'var(--grey)' }}>
              Resend code in <strong>{countdown}s</strong>
            </span>
          ) : (
            <button
              type="button"
              onClick={handleResend}
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
              <RefreshCw size={14} /> Resend OTP
            </button>
          )}
        </div>
      </div>
    </div>
  );
};
