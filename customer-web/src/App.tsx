import React from 'react';
import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom';
import { AuthProvider, useAuth } from './context/AuthContext';
import { NotificationProvider } from './context/NotificationContext';
import { AppLayout } from './components/layout/AppLayout';

// Pages
import { HomePage } from './pages/home/HomePage';
import { SearchRidesPage } from './pages/search/SearchRidesPage';
import { RideDetailsPage } from './pages/rides/RideDetailsPage';
import { BookRidePage } from './pages/rides/BookRidePage';
import { CreateRidePage } from './pages/rides/CreateRidePage';
import { MyRidesPage } from './pages/rides/MyRidesPage';
import { VehiclesPage } from './pages/vehicles/VehiclesPage';
import { ProfilePage } from './pages/profile/ProfilePage';
import { NotificationsPage } from './pages/notifications/NotificationsPage';

// Auth Pages
import { LoginPage } from './pages/auth/LoginPage';
import { OtpPage } from './pages/auth/OtpPage';
import { PasscodeLoginPage } from './pages/auth/PasscodeLoginPage';
import { PinSetupPage } from './pages/auth/PinSetupPage';
import { SignupPage } from './pages/auth/SignupPage';

const ProtectedRoute: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const { isAuthenticated, loading } = useAuth();

  if (loading) {
    return (
      <div style={{ minHeight: '100vh', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
        <div style={{ color: 'var(--blue)', fontWeight: 600 }}>Loading AbhiShare...</div>
      </div>
    );
  }

  if (!isAuthenticated) {
    return <Navigate to="/login" replace />;
  }

  return <>{children}</>;
};

export default function App() {
  return (
    <BrowserRouter>
      <AuthProvider>
        <NotificationProvider>
          <Routes>
            {/* Public Auth Routes */}
            <Route path="/login" element={<LoginPage />} />
            <Route path="/login/otp" element={<OtpPage />} />
            <Route path="/login/passcode" element={<PasscodeLoginPage />} />
            <Route path="/signup" element={<SignupPage />} />
            <Route
              path="/pin-setup"
              element={
                <ProtectedRoute>
                  <PinSetupPage />
                </ProtectedRoute>
              }
            />

            {/* App Layout Routes */}
            <Route element={<AppLayout />}>
              <Route path="/" element={<HomePage />} />
              <Route path="/search" element={<SearchRidesPage />} />
              <Route path="/rides/:rideId" element={<RideDetailsPage />} />

              {/* Protected Customer Routes */}
              <Route
                path="/rides/:rideId/book"
                element={
                  <ProtectedRoute>
                    <BookRidePage />
                  </ProtectedRoute>
                }
              />
              <Route
                path="/create-ride"
                element={
                  <ProtectedRoute>
                    <CreateRidePage />
                  </ProtectedRoute>
                }
              />
              <Route
                path="/my-rides"
                element={
                  <ProtectedRoute>
                    <MyRidesPage />
                  </ProtectedRoute>
                }
              />
              <Route
                path="/vehicles"
                element={
                  <ProtectedRoute>
                    <VehiclesPage />
                  </ProtectedRoute>
                }
              />
              <Route
                path="/profile"
                element={
                  <ProtectedRoute>
                    <ProfilePage />
                  </ProtectedRoute>
                }
              />
              <Route
                path="/notifications"
                element={
                  <ProtectedRoute>
                    <NotificationsPage />
                  </ProtectedRoute>
                }
              />
            </Route>

            {/* Fallback */}
            <Route path="*" element={<Navigate to="/" replace />} />
          </Routes>
        </NotificationProvider>
      </AuthProvider>
    </BrowserRouter>
  );
}
