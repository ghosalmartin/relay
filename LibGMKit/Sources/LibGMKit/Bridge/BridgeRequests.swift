import Foundation

/// JSON request bodies for RPCs whose libgm signature takes plain arguments rather
/// than a protobuf message. Field names mirror the structs in Bridge/rpc.go.
enum BridgeRequest {
    struct FetchMessages: Encodable {
        let conversation_id: String
        let count: Int64
        let cursor_id: String?
        let cursor_timestamp: Int64?
    }

    struct MarkRead: Encodable {
        let conversation_id: String
        let message_id: String
    }

    struct IDs: Encodable {
        let ids: [String]
    }

    struct FullSizeImage: Encodable {
        let message_id: String
        let action_message_id: String
    }

    struct Message: Encodable {
        let message_id: String
    }

    struct Conversation: Encodable {
        let conversation_id: String
    }

    struct UploadMedia: Encodable {
        let data: Data
        let file_name: String
        let mime_type: String
    }

    struct DownloadMedia: Encodable {
        let media_id: String
        let key: Data     // JSONEncoder writes base64, which is what Go expects for []byte
    }
}
