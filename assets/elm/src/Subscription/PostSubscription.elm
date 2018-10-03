module Subscription.PostSubscription exposing (postUpdatedDecoder, replyCreatedDecoder, subscribe, unsubscribe)

import GraphQL exposing (Document)
import Json.Decode as Decode
import Json.Encode as Encode
import Post exposing (Post)
import Reply exposing (Reply)
import Socket
import Subscription



-- SOCKETS


subscribe : String -> Cmd msg
subscribe postId =
    Socket.send (clientId postId) document (variables postId)


unsubscribe : String -> Cmd msg
unsubscribe postId =
    Socket.cancel (clientId postId)



-- DECODERS


postUpdatedDecoder : Decode.Decoder Post
postUpdatedDecoder =
    Subscription.decoder "post"
        "PostUpdated"
        "post"
        Post.decoder


replyCreatedDecoder : Decode.Decoder Reply
replyCreatedDecoder =
    Subscription.decoder "post"
        "ReplyCreated"
        "reply"
        Reply.decoder



-- INTERNAL


clientId : String -> String
clientId id =
    "post_subscription_" ++ id


document : Document
document =
    GraphQL.toDocument
        """
        subscription PostSubscription(
          $postId: ID!
        ) {
          postSubscription(postId: $postId) {
            __typename
            ... on PostUpdatedPayload {
              post {
                ...PostFields
              }
            }
            ... on ReplyCreatedPayload {
              reply {
                ...ReplyFields
              }
            }
          }
        }
        """
        [ Post.fragment
        , Reply.fragment
        ]


variables : String -> Maybe Encode.Value
variables postId =
    Just <|
        Encode.object
            [ ( "postId", Encode.string postId )
            ]
