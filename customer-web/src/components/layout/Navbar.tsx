import React, { useState } from 'react';
import { Link, useLocation, useNavigate } from 'react-router-dom';
import {
  Car,
  Search,
  PlusCircle,
  Calendar,
  ShieldCheck,
  Bell,
  User as UserIcon,
  LogOut,
  ChevronDown,
} from 'lucide-react';
import { useAuth } from '../../context/AuthContext';
import { useNotifications } from '../../context/NotificationContext';

export const Navbar: React.FC = () => {
  const { user, logout, isAuthenticated } = useAuth();
  const { unreadCount } = useNotifications();
  const location = useLocation();
  const navigate = useNavigate();
  const [dropdownOpen, setDropdownOpen] = useState(false);

  const navLinks = [
    { to: '/', label: 'Home', icon: Car },
    { to: '/search', label: 'Search Rides', icon: Search },
    { to: '/create-ride', label: 'Offer Ride', icon: PlusCircle },
    { to: '/my-rides', label: 'My Bookings', icon: Calendar },
    { to: '/vehicles', label: 'My Vehicles', icon: ShieldCheck },
  ];

  const handleLogout = async () => {
    setDropdownOpen(false);
    await logout();
    navigate('/login');
  };

  return (
    <header className="desktop-header">
      <div className="app-container" style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
        {/* Brand Logo */}
        <Link to="/" style={{ display: 'flex', alignItems: 'center', gap: '0.5rem', textDecoration: 'none' }}>
          <div
            style={{
              width: 38,
              height: 38,
              borderRadius: '10px',
              background: 'linear-gradient(135deg, var(--blue), var(--green))',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              color: '#fff',
              boxShadow: '0 2px 8px rgba(11, 79, 216, 0.25)',
            }}
          >
            <Car size={22} strokeWidth={2.4} />
          </div>
          <span style={{ fontSize: '1.35rem', fontWeight: 800, letterSpacing: '-0.5px' }}>
            <span style={{ color: 'var(--blue)' }}>Abhi</span>
            <span style={{ color: 'var(--green)' }}>Share</span>
          </span>
        </Link>

        {/* Desktop Navigation Links */}
        <nav className="desktop-nav-links" style={{ display: 'flex', alignItems: 'center', gap: '0.4rem' }}>
          {navLinks.map((link) => {
            const Icon = link.icon;
            const isActive = location.pathname === link.to;
            return (
              <Link
                key={link.to}
                to={link.to}
                className={`nav-link ${isActive ? 'active' : ''}`}
              >
                <Icon size={18} />
                <span>{link.label}</span>
              </Link>
            );
          })}
        </nav>

        {/* Right Action Icons: Notifications & User */}
        <div style={{ display: 'flex', alignItems: 'center', gap: '1rem' }}>
          {isAuthenticated ? (
            <>
              {/* Notification Bell */}
              <Link
                to="/notifications"
                style={{
                  position: 'relative',
                  width: 40,
                  height: 40,
                  borderRadius: '10px',
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  color: 'var(--navy)',
                  background: 'var(--bg-header)',
                  transition: 'background 0.2s',
                }}
                title="Notifications"
              >
                <Bell size={20} />
                {unreadCount > 0 && (
                  <span
                    style={{
                      position: 'absolute',
                      top: 7,
                      right: 7,
                      width: 9,
                      height: 9,
                      borderRadius: '50%',
                      background: 'var(--red)',
                      border: '2px solid #ffffff',
                    }}
                  />
                )}
              </Link>

              {/* User Dropdown */}
              <div style={{ position: 'relative' }}>
                <button
                  type="button"
                  onClick={() => setDropdownOpen(!dropdownOpen)}
                  style={{
                    display: 'flex',
                    alignItems: 'center',
                    gap: '0.6rem',
                    padding: '0.35rem 0.65rem 0.35rem 0.35rem',
                    borderRadius: 'var(--radius-full)',
                    border: '1.5px solid var(--grey-border)',
                    background: '#ffffff',
                    cursor: 'pointer',
                  }}
                >
                  <div
                    style={{
                      width: 32,
                      height: 32,
                      borderRadius: '50%',
                      background: 'linear-gradient(135deg, var(--blue-accent), var(--blue))',
                      color: '#ffffff',
                      display: 'flex',
                      alignItems: 'center',
                      justifyContent: 'center',
                      fontWeight: 700,
                      fontSize: '0.85rem',
                    }}
                  >
                    {user?.full_name?.charAt(0).toUpperCase() || <UserIcon size={16} />}
                  </div>
                  <span
                    style={{
                      fontWeight: 600,
                      fontSize: '0.875rem',
                      color: 'var(--navy)',
                      maxWidth: '100px',
                      whiteSpace: 'nowrap',
                      overflow: 'hidden',
                      textOverflow: 'ellipsis',
                    }}
                  >
                    {user?.full_name?.split(' ')[0] || 'Account'}
                  </span>
                  <ChevronDown size={14} color="var(--grey)" />
                </button>

                {/* Dropdown Menu */}
                {dropdownOpen && (
                  <div
                    style={{
                      position: 'absolute',
                      right: 0,
                      top: '115%',
                      width: 200,
                      background: '#ffffff',
                      borderRadius: 'var(--radius-lg)',
                      boxShadow: 'var(--shadow-lg)',
                      border: '1px solid var(--grey-border)',
                      padding: '0.5rem',
                      zIndex: 200,
                    }}
                  >
                    <div style={{ padding: '0.5rem 0.75rem', borderBottom: '1px solid var(--grey-border)' }}>
                      <p style={{ fontWeight: 700, color: 'var(--navy)', fontSize: '0.9rem' }}>
                        {user?.full_name || 'User'}
                      </p>
                      <p style={{ color: 'var(--grey)', fontSize: '0.75rem' }}>
                        {user?.phone || user?.email || ''}
                      </p>
                    </div>
                    <Link
                      to="/profile"
                      onClick={() => setDropdownOpen(false)}
                      style={{
                        display: 'flex',
                        alignItems: 'center',
                        gap: '0.6rem',
                        padding: '0.6rem 0.75rem',
                        fontSize: '0.875rem',
                        color: 'var(--navy)',
                        borderRadius: 'var(--radius-md)',
                      }}
                      onMouseEnter={(e) => (e.currentTarget.style.backgroundColor = 'var(--bg-header)')}
                      onMouseLeave={(e) => (e.currentTarget.style.backgroundColor = 'transparent')}
                    >
                      <UserIcon size={16} />
                      My Profile
                    </Link>
                    <Link
                      to="/vehicles"
                      onClick={() => setDropdownOpen(false)}
                      style={{
                        display: 'flex',
                        alignItems: 'center',
                        gap: '0.6rem',
                        padding: '0.6rem 0.75rem',
                        fontSize: '0.875rem',
                        color: 'var(--navy)',
                        borderRadius: 'var(--radius-md)',
                      }}
                      onMouseEnter={(e) => (e.currentTarget.style.backgroundColor = 'var(--bg-header)')}
                      onMouseLeave={(e) => (e.currentTarget.style.backgroundColor = 'transparent')}
                    >
                      <Car size={16} />
                      My Vehicles
                    </Link>
                    <button
                      type="button"
                      onClick={handleLogout}
                      style={{
                        width: '100%',
                        display: 'flex',
                        alignItems: 'center',
                        gap: '0.6rem',
                        padding: '0.6rem 0.75rem',
                        fontSize: '0.875rem',
                        color: 'var(--red)',
                        borderRadius: 'var(--radius-md)',
                        textAlign: 'left',
                        borderTop: '1px solid var(--grey-border)',
                        marginTop: '0.25rem',
                      }}
                      onMouseEnter={(e) => (e.currentTarget.style.backgroundColor = 'var(--red-bg)')}
                      onMouseLeave={(e) => (e.currentTarget.style.backgroundColor = 'transparent')}
                    >
                      <LogOut size={16} />
                      Sign Out
                    </button>
                  </div>
                )}
              </div>
            </>
          ) : (
            <Link to="/login" className="btn btn-primary" style={{ padding: '0.5rem 1rem', fontSize: '0.875rem' }}>
              Sign In
            </Link>
          )}
        </div>
      </div>
    </header>
  );
};
