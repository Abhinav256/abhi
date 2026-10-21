package handlers

import (
	"context"
	"strconv"

	"github.com/gofiber/fiber/v2"

	"github.com/abhishare16/Abhi-Share/backend/middleware"
	"github.com/abhishare16/Abhi-Share/backend/models"
	"github.com/abhishare16/Abhi-Share/backend/services"
)

type ChatHandler struct {
	Service *services.ChatService
}

func NewChatHandler(service *services.ChatService) *ChatHandler {
	return &ChatHandler{Service: service}
}

// GetOrCreateConversation retrieves or creates a conversation for a confirmed booking.
func (h *ChatHandler) GetOrCreateConversation(c *fiber.Ctx) error {
	userID, ok := middleware.UserID(c)
	if !ok {
		return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{"error": "authenticated user required"})
	}

	var req models.GetOrCreateConversationRequest
	if err := c.BodyParser(&req); err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "invalid request body"})
	}

	conv, err := h.Service.GetOrCreateConversation(context.Background(), userID, req.BookingID)
	if err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": err.Error()})
	}

	return c.JSON(conv)
}

// ListConversations returns all conversations for the authenticated user.
func (h *ChatHandler) ListConversations(c *fiber.Ctx) error {
	userID, ok := middleware.UserID(c)
	if !ok {
		return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{"error": "authenticated user required"})
	}

	conversations, err := h.Service.ListConversations(context.Background(), userID)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": err.Error()})
	}

	if conversations == nil {
		conversations = []models.ChatConversationItem{}
	}

	return c.JSON(fiber.Map{
		"conversations": conversations,
	})
}

// GetConversation returns a single conversation item by ID.
func (h *ChatHandler) GetConversation(c *fiber.Ctx) error {
	userID, ok := middleware.UserID(c)
	if !ok {
		return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{"error": "authenticated user required"})
	}

	convID := c.Params("id")
	conv, err := h.Service.GetConversationByID(context.Background(), userID, convID)
	if err != nil {
		return c.Status(fiber.StatusNotFound).JSON(fiber.Map{"error": err.Error()})
	}

	return c.JSON(conv)
}

// GetMessages returns paginated messages for a conversation.
func (h *ChatHandler) GetMessages(c *fiber.Ctx) error {
	userID, ok := middleware.UserID(c)
	if !ok {
		return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{"error": "authenticated user required"})
	}

	convID := c.Params("id")
	limit, _ := strconv.Atoi(c.Query("limit", "50"))
	offset, _ := strconv.Atoi(c.Query("offset", "0"))

	msgs, err := h.Service.GetMessages(context.Background(), userID, convID, limit, offset)
	if err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": err.Error()})
	}

	if msgs == nil {
		msgs = []models.ChatMessage{}
	}

	return c.JSON(fiber.Map{
		"messages": msgs,
	})
}

// SendMessage sends a message in a conversation.
func (h *ChatHandler) SendMessage(c *fiber.Ctx) error {
	userID, ok := middleware.UserID(c)
	if !ok {
		return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{"error": "authenticated user required"})
	}

	convID := c.Params("id")
	var req models.SendMessageRequest
	if err := c.BodyParser(&req); err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "invalid request body"})
	}

	msg, err := h.Service.SendMessage(context.Background(), userID, convID, req)
	if err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": err.Error()})
	}

	return c.Status(fiber.StatusCreated).JSON(msg)
}

// MarkMessagesAsRead marks incoming messages as read in a conversation.
func (h *ChatHandler) MarkMessagesAsRead(c *fiber.Ctx) error {
	userID, ok := middleware.UserID(c)
	if !ok {
		return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{"error": "authenticated user required"})
	}

	convID := c.Params("id")
	count, err := h.Service.MarkMessagesAsRead(context.Background(), userID, convID)
	if err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": err.Error()})
	}

	return c.JSON(fiber.Map{
		"marked_read": count,
	})
}

// GetUnreadCount returns total unread messages count for the user.
func (h *ChatHandler) GetUnreadCount(c *fiber.Ctx) error {
	userID, ok := middleware.UserID(c)
	if !ok {
		return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{"error": "authenticated user required"})
	}

	total, err := h.Service.GetUnreadCount(context.Background(), userID)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": err.Error()})
	}

	return c.JSON(models.UnreadCountResponse{TotalUnread: total})
}

// BlockUser blocks another user.
func (h *ChatHandler) BlockUser(c *fiber.Ctx) error {
	userID, ok := middleware.UserID(c)
	if !ok {
		return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{"error": "authenticated user required"})
	}

	var req models.BlockUserRequest
	if err := c.BodyParser(&req); err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "invalid request body"})
	}

	if err := h.Service.BlockUser(context.Background(), userID, req); err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": err.Error()})
	}

	return c.JSON(fiber.Map{"message": "User blocked successfully"})
}

// ReportUser reports another user.
func (h *ChatHandler) ReportUser(c *fiber.Ctx) error {
	userID, ok := middleware.UserID(c)
	if !ok {
		return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{"error": "authenticated user required"})
	}

	var req models.ReportUserRequest
	if err := c.BodyParser(&req); err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "invalid request body"})
	}

	if err := h.Service.ReportUser(context.Background(), userID, req); err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": err.Error()})
	}

	return c.JSON(fiber.Map{"message": "Report submitted successfully"})
}
