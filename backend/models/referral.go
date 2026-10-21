package models

import "time"

type ReferralSummaryResponse struct {
	ReferralCode             string         `json:"referral_code"`
	ReferralLink             string         `json:"referral_link"`
	IsEligible               bool           `json:"is_eligible"`
	CompletedRidesAsDriver   int            `json:"completed_rides_as_driver"`
	EligibilityReason        string         `json:"eligibility_reason"`
	DailyReferralsUsed       int            `json:"daily_referrals_used"`
	DailyReferralsLimit      int            `json:"daily_referrals_limit"`
	DailyReferralsRemaining  int            `json:"daily_referrals_remaining"`
	TotalSuccessfulReferrals int            `json:"total_successful_referrals"`
	TotalRewardsEarned       float64        `json:"total_rewards_earned"`
	Referrals                []ReferralItem `json:"referrals"`
}

type ReferralItem struct {
	ID                    string     `json:"id"`
	RefereeID             string     `json:"referee_id"`
	RefereeName           string     `json:"referee_name"`
	RefereePhone          string     `json:"referee_phone"`
	Status                string     `json:"status"` // registered, ride_pending, eligible, reward_credited
	StatusDisplay         string     `json:"status_display"`
	RewardAmount          float64    `json:"reward_amount"`
	ReferrerRideCompleted bool       `json:"referrer_ride_completed"`
	RefereeRideCompleted  bool       `json:"referee_ride_completed"`
	RewardCreditedAt      *time.Time `json:"reward_credited_at,omitempty"`
	CreatedAt             time.Time  `json:"created_at"`
}

type ValidateReferralCodeRequest struct {
	ReferralCode string `json:"referral_code"`
}

type ValidateReferralCodeResponse struct {
	Valid        bool   `json:"valid"`
	ReferrerName string `json:"referrer_name,omitempty"`
	Message      string `json:"message"`
}
