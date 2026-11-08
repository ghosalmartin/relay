/// libgm's .proto files are split across packages (conversations, client, events,
/// settings, ...) that Go flattens into `gmproto`. `GM` gives Swift the same flat names.
/// The types themselves are generated into Generated/ by scripts/gen-protos.sh.
public enum GM {
    public typealias Conversation = Conversations_Conversation
    public typealias ConversationType = Conversations_ConversationType
    public typealias Message = Conversations_Message
    public typealias MessageInfo = Conversations_MessageInfo
    public typealias MessageStatusType = Conversations_MessageStatusType
    public typealias MessagePayload = Client_MessagePayload
    public typealias Participant = Conversations_Participant
    public typealias TypingData = Events_TypingData
    public typealias Settings = Settings_Settings
    public typealias Cursor = Client_Cursor
    public typealias ListConversationsRequest = Client_ListConversationsRequest
    public typealias ListConversationsResponse = Client_ListConversationsResponse
    public typealias ListMessagesResponse = Client_ListMessagesResponse
    public typealias SendMessageRequest = Client_SendMessageRequest
    public typealias SendMessageResponse = Client_SendMessageResponse
    public typealias SendReactionRequest = Client_SendReactionRequest
    public typealias SendReactionResponse = Client_SendReactionResponse
    public typealias ListContactsResponse = Client_ListContactsResponse
    public typealias GetThumbnailResponse = Client_GetThumbnailResponse
    public typealias GetFullSizeImageResponse = Client_GetFullSizeImageResponse
    public typealias DeleteMessageResponse = Client_DeleteMessageResponse
    public typealias GetOrCreateConversationRequest = Client_GetOrCreateConversationRequest
    public typealias GetOrCreateConversationResponse = Client_GetOrCreateConversationResponse
    public typealias UpdateConversationRequest = Client_UpdateConversationRequest
    public typealias UpdateConversationResponse = Client_UpdateConversationResponse
}
