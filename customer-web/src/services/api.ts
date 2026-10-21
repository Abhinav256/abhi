import type {
  User,
  Vehicle,
  Ride,
  Booking,
  NotificationItem,
  PendingRatingResponse,
  RecurringSchedule,
  SavedLocation,
} from '../types';

const TOKEN_KEY = 'abhishare_session_token';
const USER_KEY = 'abhishare_user_id';
const BASE_URL = import.meta.env.VITE_API_BASE_URL || (import.meta.env.PROD ? 'https://abhishare-api.onrender.com' : '');

class ApiService {
  private getHeaders(authenticated = false, isFormData = false): HeadersInit {
    const headers: Record<string, string> = {};
    if (!isFormData) {
      headers['Content-Type'] = 'application/json';
    }
    if (authenticated) {
      const token = localStorage.getItem(TOKEN_KEY);
      if (token) {
        headers['Authorization'] = `Bearer ${token}`;
      }
    }
    return headers;
  }

  private async handleResponse<T>(res: Response): Promise<T> {
    let data: any = {};
    const text = await res.text();
    if (text) {
      try {
        data = JSON.parse(text);
      } catch {
        data = { message: text };
      }
    }
    if (!res.ok) {
      const errorMsg = data.error || data.message || `Request failed (${res.status})`;
      throw new Error(errorMsg);
    }
    return data as T;
  }

  // Token management
  setSession(token: string, userId: string) {
    localStorage.setItem(TOKEN_KEY, token);
    localStorage.setItem(USER_KEY, userId);
  }

  clearSession() {
    localStorage.removeItem(TOKEN_KEY);
    localStorage.removeItem(USER_KEY);
  }

  getToken(): string | null {
    return localStorage.getItem(TOKEN_KEY);
  }

  getUserId(): string | null {
    return localStorage.getItem(USER_KEY);
  }

  isLoggedIn(): boolean {
    return !!this.getToken();
  }

  // Health
  async healthCheck(): Promise<{ status: string }> {
    const res = await fetch(`${BASE_URL}/health`);
    return this.handleResponse(res);
  }

  // Auth APIs
  async checkAuthIdentifier(identifier: string): Promise<{
    exists: boolean;
    has_pin: boolean;
    account_locked?: boolean;
    type?: string;
  }> {
    const res = await fetch(`${BASE_URL}/auth/start`, {
      method: 'POST',
      headers: this.getHeaders(false),
      body: JSON.stringify({ identifier }),
    });
    return this.handleResponse(res);
  }

  async sendOTPUniversal(identifier: string): Promise<{
    message: string;
    type?: string;
    next_resend_allowed_at?: string;
  }> {
    const res = await fetch(`${BASE_URL}/auth/unified/send-otp`, {
      method: 'POST',
      headers: this.getHeaders(false),
      body: JSON.stringify({ identifier }),
    });
    return this.handleResponse(res);
  }

  async verifyOTPAndCheck(
    identifier: string,
    otp: string
  ): Promise<{
    exists: boolean;
    type?: string;
    token?: string;
    user?: User;
  }> {
    const res = await fetch(`${BASE_URL}/auth/unified/verify-check`, {
      method: 'POST',
      headers: this.getHeaders(false),
      body: JSON.stringify({ identifier, otp }),
    });
    return this.handleResponse(res);
  }

  async completeSignup(payload: {
    full_name: string;
    phone?: string;
    email?: string;
    date_of_birth?: string;
    gender?: string;
    pin: string;
    referral_code?: string;
  }): Promise<{
    token: string;
    user: User;
  }> {
    const res = await fetch(`${BASE_URL}/auth/unified/complete-signup`, {
      method: 'POST',
      headers: this.getHeaders(false),
      body: JSON.stringify(payload),
    });
    return this.handleResponse(res);
  }

  async loginWithPasscode(identifier: string, pin: string): Promise<{
    token: string;
    user: User;
  }> {
    const res = await fetch(`${BASE_URL}/auth/login/passcode`, {
      method: 'POST',
      headers: this.getHeaders(false),
      body: JSON.stringify({ identifier, pin }),
    });
    return this.handleResponse(res);
  }

  async setPIN(pin: string): Promise<void> {
    const res = await fetch(`${BASE_URL}/auth/pin/set`, {
      method: 'POST',
      headers: this.getHeaders(true),
      body: JSON.stringify({ pin }),
    });
    return this.handleResponse(res);
  }

  async verifyPIN(pin: string): Promise<boolean> {
    const res = await fetch(`${BASE_URL}/auth/pin/verify`, {
      method: 'POST',
      headers: this.getHeaders(true),
      body: JSON.stringify({ pin }),
    });
    const data = await this.handleResponse<{ valid: boolean }>(res);
    return data.valid === true;
  }

  async changePIN(oldPin: string, newPin: string): Promise<void> {
    const res = await fetch(`${BASE_URL}/auth/pin/change`, {
      method: 'POST',
      headers: this.getHeaders(true),
      body: JSON.stringify({ old_pin: oldPin, new_pin: newPin }),
    });
    return this.handleResponse(res);
  }

  async getCurrentUser(): Promise<User> {
    const res = await fetch(`${BASE_URL}/auth/me`, {
      headers: this.getHeaders(true),
    });
    return this.handleResponse(res);
  }

  async updateProfile(payload: {
    full_name?: string;
    nickname?: string;
    date_of_birth?: string;
    gender?: string;
  }): Promise<{ user: User }> {
    const res = await fetch(`${BASE_URL}/auth/me`, {
      method: 'PUT',
      headers: this.getHeaders(true),
      body: JSON.stringify(payload),
    });
    return this.handleResponse(res);
  }

  async logout(): Promise<void> {
    try {
      await fetch(`${BASE_URL}/auth/logout`, {
        method: 'POST',
        headers: this.getHeaders(true),
      });
    } finally {
      this.clearSession();
    }
  }

  // Vehicles
  async getVehicles(): Promise<Vehicle[]> {
    const res = await fetch(`${BASE_URL}/vehicles`, {
      headers: this.getHeaders(true),
    });
    const data = await this.handleResponse<any>(res);
    if (Array.isArray(data)) return data;
    if (Array.isArray(data.vehicles)) return data.vehicles;
    return [];
  }

  async getVehicle(vehicleId: string): Promise<Vehicle> {
    const res = await fetch(`${BASE_URL}/vehicles/${vehicleId}`, {
      headers: this.getHeaders(true),
    });
    return this.handleResponse(res);
  }

  async addVehicle(payload: {
    vehicle_number: string;
    vehicle_type: string;
    model: string;
  }): Promise<{ vehicle_id: string; message: string }> {
    const res = await fetch(`${BASE_URL}/vehicles`, {
      method: 'POST',
      headers: this.getHeaders(true),
      body: JSON.stringify(payload),
    });
    return this.handleResponse(res);
  }

  async deleteVehicle(vehicleId: string): Promise<void> {
    const res = await fetch(`${BASE_URL}/vehicles/${vehicleId}`, {
      method: 'DELETE',
      headers: this.getHeaders(true),
    });
    return this.handleResponse(res);
  }

  async uploadVehicleImage(vehicleId: string, imageType: 'rc' | 'vehicle', file: File): Promise<{ url: string }> {
    const formData = new FormData();
    formData.append('vehicle_id', vehicleId);
    formData.append('type', imageType);
    formData.append('image', file);

    const res = await fetch(`${BASE_URL}/upload/vehicle-image`, {
      method: 'POST',
      headers: this.getHeaders(true, true),
      body: formData,
    });
    return this.handleResponse(res);
  }

  // Rides
  async createRide(payload: {
    vehicle_id: string;
    origin: string;
    destination: string;
    journey_date: string;
    departure_time: string;
    available_seats: number;
    price_per_seat: number;
    instant_booking?: boolean;
    notes?: string;
  }): Promise<{ ride_id: string; message: string; ride?: Ride }> {
    const res = await fetch(`${BASE_URL}/rides`, {
      method: 'POST',
      headers: this.getHeaders(true),
      body: JSON.stringify(payload),
    });
    return this.handleResponse(res);
  }

  async uploadRideSelfie(rideId: string, selfie: File): Promise<{ url: string }> {
    const formData = new FormData();
    formData.append('selfie', selfie);

    const res = await fetch(`${BASE_URL}/rides/${rideId}/selfie`, {
      method: 'POST',
      headers: this.getHeaders(true, true),
      body: formData,
    });
    return this.handleResponse(res);
  }

  async publishRide(rideId: string): Promise<void> {
    const res = await fetch(`${BASE_URL}/rides/${rideId}/publish`, {
      method: 'POST',
      headers: this.getHeaders(true),
    });
    return this.handleResponse(res);
  }

  async searchRides(params: {
    fromLocation?: string;
    toLocation?: string;
    journeyDate?: string;
  }): Promise<Ride[]> {
    const query = new URLSearchParams();
    if (params.fromLocation) query.append('from', params.fromLocation);
    if (params.toLocation) query.append('to', params.toLocation);
    if (params.journeyDate) query.append('date', params.journeyDate);

    const res = await fetch(`${BASE_URL}/rides?${query.toString()}`, {
      headers: this.getHeaders(false),
    });
    const data = await this.handleResponse<any>(res);
    if (Array.isArray(data)) return data;
    if (Array.isArray(data.rides)) return data.rides;
    return [];
  }

  async getRideDetail(rideId: string): Promise<Ride> {
    const res = await fetch(`${BASE_URL}/rides/${rideId}`, {
      headers: this.getHeaders(false),
    });
    const data = await this.handleResponse<any>(res);
    if (data.ride) return data.ride;
    return data;
  }

  async getMyRides(): Promise<Ride[]> {
    const res = await fetch(`${BASE_URL}/rides/me`, {
      headers: this.getHeaders(true),
    });
    const data = await this.handleResponse<any>(res);
    if (Array.isArray(data)) return data;
    if (Array.isArray(data.created_rides)) return data.created_rides;
    if (Array.isArray(data.rides)) return data.rides;
    return [];
  }

  async completeRide(rideId: string): Promise<void> {
    const res = await fetch(`${BASE_URL}/rides/${rideId}/complete`, {
      method: 'POST',
      headers: this.getHeaders(true),
    });
    return this.handleResponse(res);
  }

  async cancelRide(rideId: string): Promise<void> {
    const res = await fetch(`${BASE_URL}/rides/${rideId}/cancel`, {
      method: 'POST',
      headers: this.getHeaders(true),
    });
    return this.handleResponse(res);
  }

  async deleteDraft(rideId: string): Promise<void> {
    const res = await fetch(`${BASE_URL}/rides/${rideId}/draft`, {
      method: 'DELETE',
      headers: this.getHeaders(true),
    });
    return this.handleResponse(res);
  }

  // Bookings
  async createBooking(payload: {
    ride_id: string;
    seats_booked: number;
    payment_mode: string;
    passengers: Array<{ name: string; age: number; gender: string }>;
  }): Promise<{ booking_id: string; message: string }> {
    const res = await fetch(`${BASE_URL}/bookings`, {
      method: 'POST',
      headers: this.getHeaders(true),
      body: JSON.stringify(payload),
    });
    return this.handleResponse(res);
  }

  async getMyBookings(): Promise<Booking[]> {
    const res = await fetch(`${BASE_URL}/bookings/me`, {
      headers: this.getHeaders(true),
    });
    const data = await this.handleResponse<any>(res);
    if (Array.isArray(data)) return data;
    if (Array.isArray(data.bookings)) return data.bookings;
    return [];
  }

  async getRideBookings(rideId: string): Promise<Booking[]> {
    const res = await fetch(`${BASE_URL}/bookings/ride/${rideId}`, {
      headers: this.getHeaders(true),
    });
    const data = await this.handleResponse<any>(res);
    if (Array.isArray(data)) return data;
    if (Array.isArray(data.bookings)) return data.bookings;
    return [];
  }

  async getBooking(bookingId: string): Promise<Booking> {
    const res = await fetch(`${BASE_URL}/bookings/${bookingId}`, {
      headers: this.getHeaders(true),
    });
    return this.handleResponse(res);
  }

  async cancelBooking(bookingId: string): Promise<void> {
    const res = await fetch(`${BASE_URL}/bookings/${bookingId}/cancel`, {
      method: 'POST',
      headers: this.getHeaders(true),
    });
    return this.handleResponse(res);
  }

  // Notifications
  async getNotifications(): Promise<NotificationItem[]> {
    const res = await fetch(`${BASE_URL}/notifications`, {
      headers: this.getHeaders(true),
    });
    const data = await this.handleResponse<any>(res);
    if (Array.isArray(data)) return data;
    if (Array.isArray(data.notifications)) return data.notifications;
    return [];
  }

  async markNotificationRead(id: string): Promise<void> {
    const res = await fetch(`${BASE_URL}/notifications/${id}/read`, {
      method: 'PUT',
      headers: this.getHeaders(true),
    });
    return this.handleResponse(res);
  }

  // Ratings
  async getPendingRating(): Promise<PendingRatingResponse> {
    const res = await fetch(`${BASE_URL}/ratings/pending`, {
      headers: this.getHeaders(true),
    });
    return this.handleResponse(res);
  }

  async submitRatings(payload: {
    ride_id: string;
    ratings: Array<{
      ratee_id: string;
      role: string;
      rating: number;
      feedback?: string;
    }>;
  }): Promise<void> {
    const res = await fetch(`${BASE_URL}/ratings`, {
      method: 'POST',
      headers: this.getHeaders(true),
      body: JSON.stringify(payload),
    });
    return this.handleResponse(res);
  }

  async getMyRatingSummary(): Promise<any> {
    const res = await fetch(`${BASE_URL}/ratings/me`, {
      headers: this.getHeaders(true),
    });
    return this.handleResponse(res);
  }

  // Recurring Schedules
  async getRecurringSchedules(): Promise<RecurringSchedule[]> {
    const res = await fetch(`${BASE_URL}/recurring-schedules`, {
      headers: this.getHeaders(true),
    });
    const data = await this.handleResponse<any>(res);
    if (Array.isArray(data)) return data;
    if (Array.isArray(data.schedules)) return data.schedules;
    return [];
  }

  async createRecurringSchedule(payload: any): Promise<any> {
    const res = await fetch(`${BASE_URL}/recurring-schedules`, {
      method: 'POST',
      headers: this.getHeaders(true),
      body: JSON.stringify(payload),
    });
    return this.handleResponse(res);
  }

  async uploadRecurringSelfie(scheduleId: string, selfie: File): Promise<any> {
    const formData = new FormData();
    formData.append('selfie', selfie);

    const res = await fetch(`${BASE_URL}/recurring-schedules/${scheduleId}/selfie`, {
      method: 'POST',
      headers: this.getHeaders(true, true),
      body: formData,
    });
    return this.handleResponse(res);
  }

  async publishRecurringSchedule(scheduleId: string): Promise<any> {
    const res = await fetch(`${BASE_URL}/recurring-schedules/${scheduleId}/publish`, {
      method: 'POST',
      headers: this.getHeaders(true),
    });
    return this.handleResponse(res);
  }

  async pauseRecurringSchedule(scheduleId: string): Promise<void> {
    const res = await fetch(`${BASE_URL}/recurring-schedules/${scheduleId}/pause`, {
      method: 'PUT',
      headers: this.getHeaders(true),
    });
    return this.handleResponse(res);
  }

  async resumeRecurringSchedule(scheduleId: string): Promise<void> {
    const res = await fetch(`${BASE_URL}/recurring-schedules/${scheduleId}/resume`, {
      method: 'PUT',
      headers: this.getHeaders(true),
    });
    return this.handleResponse(res);
  }

  async cancelRecurringSchedule(scheduleId: string): Promise<void> {
    const res = await fetch(`${BASE_URL}/recurring-schedules/${scheduleId}/cancel`, {
      method: 'PUT',
      headers: this.getHeaders(true),
    });
    return this.handleResponse(res);
  }

  // Saved Locations
  async getLocations(): Promise<SavedLocation[]> {
    const res = await fetch(`${BASE_URL}/locations`, {
      headers: this.getHeaders(true),
    });
    const data = await this.handleResponse<any>(res);
    if (Array.isArray(data)) return data;
    return [];
  }

  async saveLocation(name: string, address: string): Promise<any> {
    const res = await fetch(`${BASE_URL}/locations`, {
      method: 'POST',
      headers: this.getHeaders(true),
      body: JSON.stringify({ name, address }),
    });
    return this.handleResponse(res);
  }
}

export const api = new ApiService();
