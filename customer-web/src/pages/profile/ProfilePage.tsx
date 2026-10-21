import React, { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import {
  User as UserIcon,
  Phone,
  Mail,
  Calendar,
  Star,
  Edit2,
  LogOut,
  Car,
  Bell,
  ShieldCheck,
  CheckCircle,
} from 'lucide-react';
import { useAuth } from '../../context/AuthContext';
import { api } from '../../services/api';
import { Modal } from '../../components/ui/Modal';

export const ProfilePage: React.FC = () => {
  const { user, refreshUser, logout } = useAuth();
  const navigate = useNavigate();

  // Edit Profile Modal State
  const [isEditModalOpen, setIsEditModalOpen] = useState(false);
  const [fullName, setFullName] = useState(user?.full_name || '');
  const [nickname, setNickname] = useState(user?.nickname || '');
  const [dateOfBirth, setDateOfBirth] = useState(user?.date_of_birth || '');
  const [gender, setGender] = useState(user?.gender || 'male');

  const [saving, setSaving] = useState(false);
  const [successMessage, setSuccessMessage] = useState<string | null>(null);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  const handleEditClick = () => {
    setFullName(user?.full_name || '');
    setNickname(user?.nickname || '');
    setDateOfBirth(user?.date_of_birth || '');
    setGender(user?.gender || 'male');
    setIsEditModalOpen(true);
  };

  const handleSaveProfile = async (e: React.FormEvent) => {
    e.preventDefault();
    try {
      setSaving(true);
      setErrorMessage(null);
      await api.updateProfile({
        full_name: fullName.trim(),
        nickname: nickname.trim() || undefined,
        date_of_birth: dateOfBirth || undefined,
        gender,
      });
      await refreshUser();
      setSuccessMessage('Profile updated successfully!');
      setTimeout(() => setSuccessMessage(null), 3000);
      setIsEditModalOpen(false);
    } catch (err: any) {
      setErrorMessage(err.message || 'Failed to update profile');
    } finally {
      setSaving(false);
    }
  };

  const handleLogout = async () => {
    await logout();
    navigate('/login');
  };

  return (
    <div className="animate-fade-in" style={{ padding: '2rem 0' }}>
      <div className="app-container" style={{ maxWidth: 680 }}>
        {/* Header */}
        <div style={{ marginBottom: '1.5rem' }}>
          <h1 style={{ fontSize: '1.75rem', fontWeight: 800, color: 'var(--navy)', marginBottom: '0.25rem' }}>
            My Account & Profile
          </h1>
          <p style={{ color: 'var(--grey)', fontSize: '0.95rem' }}>
            Manage your personal profile and account preferences.
          </p>
        </div>

        {successMessage && (
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
            <span>{successMessage}</span>
          </div>
        )}

        {/* Profile Card */}
        <div
          className="card"
          style={{
            padding: '2rem',
            background: '#ffffff',
            border: '1.5px solid var(--grey-border)',
            boxShadow: 'var(--shadow-md)',
            marginBottom: '1.5rem',
          }}
        >
          <div
            style={{
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'space-between',
              marginBottom: '1.5rem',
              flexWrap: 'wrap',
              gap: '1rem',
            }}
          >
            <div style={{ display: 'flex', alignItems: 'center', gap: '1.25rem' }}>
              <div
                style={{
                  width: 72,
                  height: 72,
                  borderRadius: '50%',
                  background: 'linear-gradient(135deg, var(--blue), var(--green))',
                  color: '#ffffff',
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  fontWeight: 800,
                  fontSize: '1.75rem',
                  boxShadow: '0 4px 12px rgba(11, 79, 216, 0.2)',
                }}
              >
                {user?.full_name?.charAt(0).toUpperCase() || <UserIcon size={32} />}
              </div>

              <div>
                <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
                  <h2 style={{ fontSize: '1.35rem', fontWeight: 800, color: 'var(--navy)' }}>
                    {user?.full_name || 'Valued Member'}
                  </h2>
                  <ShieldCheck size={18} color="var(--green)" />
                </div>
                {user?.nickname && (
                  <p style={{ fontSize: '0.85rem', color: 'var(--grey)', fontWeight: 500 }}>
                    "{user.nickname}"
                  </p>
                )}
                <div style={{ display: 'flex', alignItems: 'center', gap: '0.35rem', marginTop: '0.25rem' }}>
                  <Star size={15} fill="var(--amber)" color="var(--amber)" />
                  <span style={{ fontWeight: 700, fontSize: '0.9rem', color: 'var(--navy)' }}>
                    {user?.average_rating ? Number(user.average_rating).toFixed(1) : '5.0'}
                  </span>
                  <span style={{ fontSize: '0.8rem', color: 'var(--grey)' }}>Community Rating</span>
                </div>
              </div>
            </div>

            <button
              type="button"
              onClick={handleEditClick}
              className="btn btn-outline"
              style={{ padding: '0.5rem 1rem', fontSize: '0.85rem' }}
            >
              <Edit2 size={15} />
              Edit Profile
            </button>
          </div>

          {/* Details Grid */}
          <div
            style={{
              display: 'grid',
              gridTemplateColumns: 'repeat(auto-fit, minmax(220px, 1fr))',
              gap: '1rem',
              background: 'var(--bg)',
              padding: '1.25rem',
              borderRadius: 'var(--radius-lg)',
              border: '1px solid var(--grey-border)',
            }}
          >
            <div>
              <span style={{ fontSize: '0.75rem', color: 'var(--grey)', fontWeight: 600, display: 'flex', alignItems: 'center', gap: '0.35rem' }}>
                <Phone size={13} /> Mobile Number
              </span>
              <p style={{ fontWeight: 600, color: 'var(--navy)', marginTop: '0.2rem' }}>
                {user?.phone || 'Not linked'}
              </p>
            </div>

            <div>
              <span style={{ fontSize: '0.75rem', color: 'var(--grey)', fontWeight: 600, display: 'flex', alignItems: 'center', gap: '0.35rem' }}>
                <Mail size={13} /> Email Address
              </span>
              <p style={{ fontWeight: 600, color: 'var(--navy)', marginTop: '0.2rem' }}>
                {user?.email || 'Not linked'}
              </p>
            </div>

            <div>
              <span style={{ fontSize: '0.75rem', color: 'var(--grey)', fontWeight: 600, display: 'flex', alignItems: 'center', gap: '0.35rem' }}>
                <Calendar size={13} /> Date of Birth
              </span>
              <p style={{ fontWeight: 600, color: 'var(--navy)', marginTop: '0.2rem' }}>
                {user?.date_of_birth ? new Date(user.date_of_birth).toLocaleDateString() : 'Not provided'}
              </p>
            </div>

            <div>
              <span style={{ fontSize: '0.75rem', color: 'var(--grey)', fontWeight: 600 }}>
                Gender
              </span>
              <p style={{ fontWeight: 600, color: 'var(--navy)', marginTop: '0.2rem', textTransform: 'capitalize' }}>
                {user?.gender || 'Not specified'}
              </p>
            </div>
          </div>
        </div>

        {/* Quick Links Menu */}
        <div className="card" style={{ padding: '0.5rem', background: '#ffffff', border: '1.5px solid var(--grey-border)', marginBottom: '1.5rem' }}>
          <button
            type="button"
            onClick={() => navigate('/vehicles')}
            style={{
              width: '100%',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'space-between',
              padding: '1rem',
              borderRadius: 'var(--radius-md)',
              textAlign: 'left',
              cursor: 'pointer',
            }}
          >
            <div style={{ display: 'flex', alignItems: 'center', gap: '0.75rem' }}>
              <div style={{ width: 36, height: 36, borderRadius: 'var(--radius-sm)', background: 'var(--bg-header)', color: 'var(--blue)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                <Car size={18} />
              </div>
              <div>
                <h4 style={{ fontSize: '0.95rem', fontWeight: 700, color: 'var(--navy)' }}>My Vehicles</h4>
                <p style={{ fontSize: '0.8rem', color: 'var(--grey)' }}>Manage your car & bike records</p>
              </div>
            </div>
            <span style={{ color: 'var(--grey)', fontSize: '0.9rem' }}>→</span>
          </button>

          <button
            type="button"
            onClick={() => navigate('/my-rides')}
            style={{
              width: '100%',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'space-between',
              padding: '1rem',
              borderRadius: 'var(--radius-md)',
              textAlign: 'left',
              borderTop: '1px solid var(--grey-border)',
              cursor: 'pointer',
            }}
          >
            <div style={{ display: 'flex', alignItems: 'center', gap: '0.75rem' }}>
              <div style={{ width: 36, height: 36, borderRadius: 'var(--radius-sm)', background: 'var(--emerald-bg)', color: 'var(--green)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                <Calendar size={18} />
              </div>
              <div>
                <h4 style={{ fontSize: '0.95rem', fontWeight: 700, color: 'var(--navy)' }}>My Rides & Bookings</h4>
                <p style={{ fontSize: '0.8rem', color: 'var(--grey)' }}>View trip history and active tickets</p>
              </div>
            </div>
            <span style={{ color: 'var(--grey)', fontSize: '0.9rem' }}>→</span>
          </button>

          <button
            type="button"
            onClick={() => navigate('/notifications')}
            style={{
              width: '100%',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'space-between',
              padding: '1rem',
              borderRadius: 'var(--radius-md)',
              textAlign: 'left',
              borderTop: '1px solid var(--grey-border)',
              cursor: 'pointer',
            }}
          >
            <div style={{ display: 'flex', alignItems: 'center', gap: '0.75rem' }}>
              <div style={{ width: 36, height: 36, borderRadius: 'var(--radius-sm)', background: 'var(--rides-bg)', color: 'var(--blue)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                <Bell size={18} />
              </div>
              <div>
                <h4 style={{ fontSize: '0.95rem', fontWeight: 700, color: 'var(--navy)' }}>Notifications</h4>
                <p style={{ fontSize: '0.8rem', color: 'var(--grey)' }}>Alerts and ride confirmations</p>
              </div>
            </div>
            <span style={{ color: 'var(--grey)', fontSize: '0.9rem' }}>→</span>
          </button>
        </div>

        {/* Sign Out Button */}
        <button
          type="button"
          onClick={handleLogout}
          className="btn btn-danger"
          style={{ width: '100%', padding: '0.85rem' }}
        >
          <LogOut size={18} />
          Sign Out of AbhiShare
        </button>

        {/* Edit Profile Modal */}
        <Modal
          isOpen={isEditModalOpen}
          onClose={() => setIsEditModalOpen(false)}
          title="Edit Profile"
          maxWidth="480px"
        >
          <form onSubmit={handleSaveProfile}>
            {errorMessage && (
              <div
                style={{
                  background: 'var(--red-bg)',
                  color: 'var(--red)',
                  padding: '0.75rem',
                  borderRadius: 'var(--radius-md)',
                  marginBottom: '1rem',
                  fontSize: '0.85rem',
                }}
              >
                {errorMessage}
              </div>
            )}

            <div className="form-group">
              <label className="form-label">Full Name</label>
              <input
                type="text"
                value={fullName}
                onChange={(e) => setFullName(e.target.value)}
                className="input-field"
                required
              />
            </div>

            <div className="form-group">
              <label className="form-label">Nickname (Optional)</label>
              <input
                type="text"
                value={nickname}
                onChange={(e) => setNickname(e.target.value)}
                className="input-field"
              />
            </div>

            <div className="form-group">
              <label className="form-label">Date of Birth</label>
              <input
                type="date"
                value={dateOfBirth}
                onChange={(e) => setDateOfBirth(e.target.value)}
                className="input-field"
              />
            </div>

            <div className="form-group">
              <label className="form-label">Gender</label>
              <select
                value={gender}
                onChange={(e) => setGender(e.target.value)}
                className="input-field"
              >
                <option value="male">Male</option>
                <option value="female">Female</option>
                <option value="other">Other</option>
              </select>
            </div>

            <div style={{ display: 'flex', justifyContent: 'flex-end', gap: '0.75rem', marginTop: '1.5rem' }}>
              <button
                type="button"
                onClick={() => setIsEditModalOpen(false)}
                className="btn btn-outline"
                disabled={saving}
              >
                Cancel
              </button>
              <button
                type="submit"
                className="btn btn-primary"
                disabled={saving}
              >
                {saving ? 'Saving...' : 'Save Changes'}
              </button>
            </div>
          </form>
        </Modal>
      </div>
    </div>
  );
};
