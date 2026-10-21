import React from 'react';
import { Bell, CheckCheck, Clock } from 'lucide-react';
import { useNotifications } from '../../context/NotificationContext';

export const NotificationsPage: React.FC = () => {
  const { notifications, loading, markAsRead } = useNotifications();

  const formatTimeAgo = (dateStr?: string) => {
    if (!dateStr) return '';
    try {
      const d = new Date(dateStr);
      const now = new Date();
      const diffMs = now.getTime() - d.getTime();
      const diffMins = Math.floor(diffMs / (60 * 1000));
      if (diffMins < 1) return 'Just now';
      if (diffMins < 60) return `${diffMins}m ago`;
      const diffHours = Math.floor(diffMins / 60);
      if (diffHours < 24) return `${diffHours}h ago`;
      const diffDays = Math.floor(diffHours / 24);
      return `${diffDays}d ago`;
    } catch {
      return dateStr;
    }
  };

  return (
    <div className="animate-fade-in" style={{ padding: '2rem 0' }}>
      <div className="app-container" style={{ maxWidth: 640 }}>
        <div style={{ marginBottom: '1.5rem' }}>
          <h1 style={{ fontSize: '1.75rem', fontWeight: 800, color: 'var(--navy)', marginBottom: '0.25rem' }}>
            Notifications
          </h1>
          <p style={{ color: 'var(--grey)', fontSize: '0.95rem' }}>
            Updates regarding your rides, bookings, and account.
          </p>
        </div>

        {loading ? (
          <div style={{ textAlign: 'center', padding: '4rem 0', color: 'var(--grey)' }}>
            Loading notifications...
          </div>
        ) : notifications.length > 0 ? (
          <div style={{ display: 'flex', flexDirection: 'column', gap: '0.85rem' }}>
            {notifications.map((n) => (
              <div
                key={n.id}
                className="card"
                style={{
                  padding: '1.25rem',
                  border: '1.5px solid var(--grey-border)',
                  background: n.is_read ? '#ffffff' : 'var(--bg-header)',
                  display: 'flex',
                  justifyContent: 'space-between',
                  alignItems: 'flex-start',
                  gap: '1rem',
                }}
              >
                <div style={{ display: 'flex', gap: '0.75rem' }}>
                  <div
                    style={{
                      width: 36,
                      height: 36,
                      borderRadius: '50%',
                      background: n.is_read ? 'var(--bg)' : 'var(--blue)',
                      color: n.is_read ? 'var(--grey)' : '#ffffff',
                      display: 'flex',
                      alignItems: 'center',
                      justifyContent: 'center',
                      flexShrink: 0,
                    }}
                  >
                    <Bell size={18} />
                  </div>
                  <div>
                    <h3 style={{ fontSize: '0.95rem', fontWeight: 700, color: 'var(--navy)', marginBottom: '0.2rem' }}>
                      {n.title}
                    </h3>
                    <p style={{ color: 'var(--grey)', fontSize: '0.85rem', lineHeight: 1.4 }}>
                      {n.message}
                    </p>
                    <span
                      style={{
                        display: 'inline-flex',
                        alignItems: 'center',
                        gap: '0.25rem',
                        fontSize: '0.75rem',
                        color: 'var(--grey-light)',
                        marginTop: '0.4rem',
                      }}
                    >
                      <Clock size={12} />
                      {formatTimeAgo(n.created_at)}
                    </span>
                  </div>
                </div>

                {!n.is_read && (
                  <button
                    type="button"
                    onClick={() => markAsRead(n.id)}
                    className="btn btn-outline"
                    style={{ padding: '0.35rem 0.65rem', fontSize: '0.75rem', flexShrink: 0 }}
                    title="Mark as read"
                  >
                    <CheckCheck size={14} />
                    Mark Read
                  </button>
                )}
              </div>
            ))}
          </div>
        ) : (
          <div
            className="card"
            style={{
              textAlign: 'center',
              padding: '4rem 1.5rem',
              border: '1.5px dashed var(--grey-border)',
              background: '#ffffff',
            }}
          >
            <Bell size={36} color="var(--grey-light)" style={{ margin: '0 auto 1rem' }} />
            <h3 style={{ fontSize: '1.15rem', fontWeight: 700, color: 'var(--navy)', marginBottom: '0.35rem' }}>
              No notifications yet
            </h3>
            <p style={{ color: 'var(--grey)', fontSize: '0.9rem' }}>
              When you receive updates about your rides and bookings, they will appear here.
            </p>
          </div>
        )}
      </div>
    </div>
  );
};
