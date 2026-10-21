export type VehicleType = 'two_wheeler' | 'five_seater' | 'seven_seater';

export interface User {
  id: string;
  full_name: string;
  nickname?: string;
  phone?: string;
  email?: string;
  date_of_birth?: string;
  gender?: 'male' | 'female' | 'other' | string;
  profile_photo?: string;
  driver_selfie_url?: string;
  avatar_url?: string;
  has_pin?: boolean;
  average_rating?: number;
  total_ratings?: number;
  rides_taken?: number;
  money_saved?: number;
  money_earned?: number;
  created_at?: string;
}

export interface Vehicle {
  id: string;
  user_id: string;
  vehicle_number: string;
  vehicle_type: VehicleType;
  model: string;
  rc_image_url?: string;
  vehicle_image_url?: string;
  is_verified?: boolean;
  created_at?: string;
}

export interface Ride {
  id: string;
  driver_id: string;
  vehicle_id: string;
  origin: string;
  destination: string;
  journey_date: string;
  departure_time: string;
  estimated_arrival_time?: string;
  available_seats: number;
  total_seats?: number;
  price_per_seat: number;
  status: 'draft' | 'selfie_uploaded' | 'active' | 'confirmed' | 'completed' | 'cancelled';
  instant_booking?: boolean;
  notes?: string;
  female_only?: boolean;
  is_women_only?: boolean;
  driver_name?: string;
  driver_rating?: number | string;
  driver_photo?: string;
  driver?: Partial<User>;
  vehicle?: Partial<Vehicle>;
  vehicle_model?: string;
  vehicle_type?: VehicleType;
  vehicle_number?: string;
  created_at?: string;
}

export interface Passenger {
  name: string;
  age: number;
  gender: 'male' | 'female' | 'other' | string;
}

export interface Booking {
  id: string;
  ride_id: string;
  passenger_id: string;
  seats_booked: number;
  total_price: number;
  payment_mode?: 'cash' | 'upi' | 'card' | string;
  status: 'pending' | 'confirmed' | 'completed' | 'cancelled';
  booking_status?: string;
  passengers?: Passenger[];
  passenger?: Partial<User>;
  ride?: Partial<Ride>;
  created_at?: string;
}

export interface NotificationItem {
  id: string;
  user_id: string;
  title: string;
  message: string;
  type?: string;
  is_read: boolean;
  created_at: string;
  data?: Record<string, unknown>;
}

export interface RatingParticipant {
  user_id: string;
  name: string;
  role: 'driver' | 'passenger';
  photo_url?: string;
  already_rated?: boolean;
}

export interface PendingRatingResponse {
  has_pending_rating: boolean;
  ride_id?: string;
  participants?: RatingParticipant[];
}

export interface RecurringSchedule {
  id: string;
  user_id: string;
  vehicle_id: string;
  origin: string;
  destination: string;
  departure_time: string;
  recurrence_type: string;
  days_of_week?: string[];
  start_date: string;
  end_date?: string;
  price_per_seat: number;
  available_seats: number;
  is_active: boolean;
  status?: string;
  created_at?: string;
  vehicle?: Partial<Vehicle>;
}

export interface SavedLocation {
  id?: string;
  name: string;
  address: string;
}
