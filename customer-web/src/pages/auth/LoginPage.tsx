import React, { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { Car, ArrowRight, ShieldCheck, AlertCircle } from 'lucide-react';
import { api } from '../../services/api';

export const LoginPage: React.FC = () => {
  const navigate = useNavigate();
  const [identifier, setIdentifier] = useState('');
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    const cleanId = identifier.trim();
    if (!cleanId) {
      setError('Please enter your mobile number or email address.');
      return;
    }

    try {
      setLoading(true);
      setError(null);

      // 1. Check if user exists & has a PIN
      const checkRes = await api.checkAuthIdentifier(cleanId);

      if (checkRes.exists && checkRes.has_pin) {
        // Direct existing user with PIN to Passcode Login!
        navigate(`/login/passcode?identifier=${encodeURIComponent(cleanId)}`);
      } else {
        // Send OTP
        await api.sendOTPUniversal(cleanId);
        navigate(`/login/otp?identifier=${encodeURIComponent(cleanId)}`);
      }
    } catch (err: any) {
      setError(err.message || 'Failed to authenticate. Please check your network.');
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
        {/* Brand */}
        <div style={{ textAlign: 'center', marginBottom: '2rem' }}>
          <div
            style={{
              width: 52,
              height: 52,
              borderRadius: 'var(--radius-xl)',
              background: 'linear-gradient(135deg, var(--blue), var(--green))',
              color: '#ffffff',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              margin: '0 auto 1rem',
              boxShadow: '0 4px 14px rgba(11, 79, 216, 0.3)',
            }}
          >
            <Car size={30} strokeWidth={2.4} />
          </div>
          <h1 style={{ fontSize: '1.75rem', fontWeight: 800, letterSpacing: '-0.5px' }}>
            <span style={{ color: 'var(--blue)' }}>Abhi</span>
            <span style={{ color: 'var(--green)' }}>Share</span>
          </h1>
          <p style={{ color: 'var(--grey)', fontSize: '0.9rem', marginTop: '0.25rem' }}>
            Smart community carpooling & ride sharing
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

        <form onSubmit={handleSubmit}>
          <div className="form-group" style={{ marginBottom: '1.5rem' }}>
            <label className="form-label">Mobile Number or Email</label>
            <input
              type="text"
              placeholder="e.g. 9876543210 or name@example.com"
              value={identifier}
              onChange={(e) => setIdentifier(e.target.value)}
              className="input-field"
              required
              autoFocus
            />
          </div>

          <button
            type="submit"
            className="btn btn-primary"
            style={{ width: '100%', padding: '0.85rem', fontSize: '1rem' }}
            disabled={loading}
          >
            {loading ? 'Verifying...' : 'Continue'}
            <ArrowRight size={18} />
          </button>
        </form>

        <div style={{ textAlign: 'center', marginTop: '2rem', fontSize: '0.8rem', color: 'var(--grey-light)' }}>
          <p style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', gap: '0.35rem' }}>
            <ShieldCheck size={14} color="var(--green)" />
            Verified & secure passenger community
          </p>
        </div>
      </div>
    </div>
  );
};
