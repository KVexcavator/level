module Route.Posts exposing
    ( Params
    , init, getSpaceSlug, getState, setState, getInboxState, setInboxState, getLastActivity, setLastActivity, getAuthor, setAuthor, getRecipients, setRecipients, isPlainText, clearFilters
    , parser
    , toString
    )

{-| Route building and parsing for the "Activity" page.


# Types

@docs Params


# API

@docs init, getSpaceSlug, getState, setState, getInboxState, setInboxState, getLastActivity, setLastActivity, getAuthor, setAuthor, getRecipients, setRecipients, isPlainText, clearFilters


# Parsing

@docs parser


# Serialization

@docs toString

-}

import InboxStateFilter exposing (InboxStateFilter)
import LastActivityFilter exposing (LastActivityFilter)
import PostStateFilter exposing (PostStateFilter)
import Url.Builder as Builder exposing (QueryParameter, absolute)
import Url.Parser as Parser exposing ((</>), (<?>), Parser, map, oneOf, s, string)
import Url.Parser.Query as Query


type Params
    = Params Internal


type alias Internal =
    { spaceSlug : String
    , state : PostStateFilter
    , inboxState : InboxStateFilter
    , lastActivity : LastActivityFilter
    , author : Maybe String
    , recipients : Maybe (List String)
    , plainText : Bool
    }



-- API


init : String -> Params
init spaceSlug =
    Params
        (Internal
            spaceSlug
            PostStateFilter.All
            InboxStateFilter.Undismissed
            LastActivityFilter.All
            Nothing
            Nothing
            False
        )


getSpaceSlug : Params -> String
getSpaceSlug (Params internal) =
    internal.spaceSlug


getState : Params -> PostStateFilter
getState (Params internal) =
    internal.state


setState : PostStateFilter -> Params -> Params
setState newState (Params internal) =
    Params { internal | state = newState }


getInboxState : Params -> InboxStateFilter
getInboxState (Params internal) =
    internal.inboxState


setInboxState : InboxStateFilter -> Params -> Params
setInboxState newState (Params internal) =
    Params { internal | inboxState = newState }


getLastActivity : Params -> LastActivityFilter
getLastActivity (Params internal) =
    internal.lastActivity


setLastActivity : LastActivityFilter -> Params -> Params
setLastActivity newState (Params internal) =
    Params { internal | lastActivity = newState }


getAuthor : Params -> Maybe String
getAuthor (Params internal) =
    internal.author


setAuthor : Maybe String -> Params -> Params
setAuthor newAuthor (Params internal) =
    Params { internal | author = newAuthor }


getRecipients : Params -> Maybe (List String)
getRecipients (Params internal) =
    internal.recipients


setRecipients : Maybe (List String) -> Params -> Params
setRecipients newRecipients (Params internal) =
    Params { internal | recipients = newRecipients }


isPlainText : Params -> Bool
isPlainText (Params internal) =
    internal.plainText


clearFilters : Params -> Params
clearFilters params =
    params
        |> setLastActivity LastActivityFilter.All
        |> setState PostStateFilter.All
        |> setInboxState InboxStateFilter.All



-- PARSING


parser : Parser (Params -> a) a
parser =
    map Params <|
        oneOf
            [ feedParser
            , inboxParser
            ]


feedParser : Parser (Internal -> a) a
feedParser =
    let
        toInternal : String -> PostStateFilter -> LastActivityFilter -> Maybe String -> Maybe (List String) -> Bool -> Internal
        toInternal spaceSlug state lastActivity author recipients plainText =
            Internal spaceSlug state InboxStateFilter.All lastActivity author recipients plainText
    in
    map toInternal
        (string
            </> s "feed"
            <?> Query.map parseFeedPostState (Query.string "state")
            <?> Query.map LastActivityFilter.fromQuery (Query.string "last_activity")
            <?> Query.string "author"
            <?> Query.map parseRecipients (Query.string "recipients")
            <?> Query.map plainTextQuery (Query.string "text")
        )


inboxParser : Parser (Internal -> a) a
inboxParser =
    map Internal
        (string
            </> s "inbox"
            <?> Query.map parseInboxPostState (Query.string "state")
            <?> Query.map parseInboxState (Query.string "inbox_state")
            <?> Query.map LastActivityFilter.fromQuery (Query.string "last_activity")
            <?> Query.string "author"
            <?> Query.map parseRecipients (Query.string "recipients")
            <?> Query.map plainTextQuery (Query.string "text")
        )


plainTextQuery : Maybe String -> Bool
plainTextQuery val =
    case val of
        Just "1" ->
            True

        _ ->
            False



-- SERIALIZATION


toString : Params -> String
toString (Params internal) =
    case internal.inboxState of
        InboxStateFilter.Undismissed ->
            absolute [ internal.spaceSlug, "inbox" ] (buildInboxQuery internal)

        InboxStateFilter.Dismissed ->
            absolute [ internal.spaceSlug, "inbox" ] (buildInboxQuery internal)

        _ ->
            absolute [ internal.spaceSlug, "feed" ] (buildFeedQuery internal)



-- PRIVATE


parseFeedPostState : Maybe String -> PostStateFilter
parseFeedPostState value =
    case value of
        Just "closed" ->
            PostStateFilter.Closed

        Just "open" ->
            PostStateFilter.Open

        _ ->
            PostStateFilter.All


parseInboxPostState : Maybe String -> PostStateFilter
parseInboxPostState value =
    case value of
        Just "closed" ->
            PostStateFilter.Closed

        Just "open" ->
            PostStateFilter.Open

        _ ->
            PostStateFilter.All


castFeedPostState : PostStateFilter -> Maybe String
castFeedPostState state =
    case state of
        PostStateFilter.Open ->
            Just "open"

        PostStateFilter.Closed ->
            Just "closed"

        PostStateFilter.All ->
            Nothing


castInboxPostState : PostStateFilter -> Maybe String
castInboxPostState state =
    case state of
        PostStateFilter.Open ->
            Just "open"

        PostStateFilter.Closed ->
            Just "closed"

        PostStateFilter.All ->
            Nothing


parseInboxState : Maybe String -> InboxStateFilter
parseInboxState value =
    case value of
        Just "dismissed" ->
            InboxStateFilter.Dismissed

        Just "all" ->
            InboxStateFilter.All

        Just "unread" ->
            InboxStateFilter.Unread

        _ ->
            InboxStateFilter.Undismissed


castInboxState : InboxStateFilter -> Maybe String
castInboxState state =
    case state of
        InboxStateFilter.Undismissed ->
            Nothing

        InboxStateFilter.Unread ->
            Just "unread"

        InboxStateFilter.Dismissed ->
            Just "dismissed"

        InboxStateFilter.All ->
            Just "all"


parseRecipients : Maybe String -> Maybe (List String)
parseRecipients maybeHandles =
    Maybe.map (String.split ",") maybeHandles


castRecipients : Maybe (List String) -> Maybe String
castRecipients maybeHandles =
    Maybe.map (String.join ",") maybeHandles


buildFeedQuery : Internal -> List QueryParameter
buildFeedQuery internal =
    buildStringParams
        [ ( "state", castFeedPostState internal.state )
        , ( "last_activity", LastActivityFilter.toQuery internal.lastActivity )
        , ( "author", internal.author )
        , ( "recipients", castRecipients internal.recipients )
        ]


buildInboxQuery : Internal -> List QueryParameter
buildInboxQuery internal =
    buildStringParams
        [ ( "state", castInboxPostState internal.state )
        , ( "inbox_state", castInboxState internal.inboxState )
        , ( "last_activity", LastActivityFilter.toQuery internal.lastActivity )
        , ( "author", internal.author )
        , ( "recipients", castRecipients internal.recipients )
        ]


buildStringParams : List ( String, Maybe String ) -> List QueryParameter
buildStringParams list =
    let
        reducer ( key, maybeValue ) queryParams =
            case maybeValue of
                Just value ->
                    Builder.string key value :: queryParams

                Nothing ->
                    queryParams
    in
    List.foldr reducer [] list
