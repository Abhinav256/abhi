import React from 'react';
import { Link, useLocation } from 'react-router-dom';
import { Home, Search, PlusCircle, Calendar, User } from 'lucide-react';

export const MobileBottomNav: React.FC = () => {
  const location = useLocation();

  const tabs = [
    { to: '/', label: 'Home', icon: Home },
    { to: '/search', label: 'Search', icon: Search },
    { to: '/create-ride', label: 'Offer', icon: PlusCircle },
    { to: '/my-rides', label: 'My Rides', icon: Calendar },
    { to: '/profile', label: 'Profile', icon: User },
  ];

  return (
    <nav className="mobile-bottom-nav">
      {tabs.map((tab) => {
        const Icon = tab.icon;
        const isActive = location.pathname === tab.to;
        return (
          <Link
            key={tab.to}
            to={tab.to}
            className={`mobile-tab-btn ${isActive ? 'active' : ''}`}
          >
            <Icon size={22} strokeWidth={isActive ? 2.5 : 1.8} />
            <span>{tab.label}</span>
          </Link>
        );
      })}
    </nav>
  );
};
