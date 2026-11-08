// libgm's .proto files use several packages (conversations, client, events,
// settings...) where Go flattens them into one `gmproto`. These aliases give
// Swift the same flat namespace: GM.Conversation, GM.SendMessageRequest, etc.
// Types come from Generated/*.pb.swift (scripts/gen-protos.sh).
public enum GM {
    public typealias Conversation = Conversations_Conversation
    public typealias Message = Conversations_Message
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
}
