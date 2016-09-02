module Dispatch exposing
  ( Config, install, add, plug, plugger, defaultConfig
  , on, onWithOptions
  , update
  )

{-| Utility module for apply multiple decoders to a single `Html.Event`.
To add support for Dispatch:

Add a message to your `Msg`

    type Msg
      = ...
      | Dispatch (List Msg)
      ...

Add call to `Dispatch.update` in update

    update : Msg -> Model -> (Model, Cmd Msg)
    update msg model =
      case msg of
        ...

      Dispatch messages ->
        Dispatch.update update messages model

        ...

Add a call to `Dispatch.on` on an element

    view : Model -> Html Msg
    view model =
      let
        decoders =
          [ Json.Decode.succeed ClickOne
          , Json.Decode.succeed ClickTwo
          , Json.Decode.map SomeMessage
              (Json.at ["target", "offsetWidth"] Json.float) ]
      in
        Html.button
          ([] ++ (case Dispatch.on "click" Dispatch decoders of
                    Just attr -> [ attr ]
                    Nothing -> []))
          [ text "Button" ]


## Events
@docs on
@docs onWithOptions
@docs update

## Advanced configuration

These are tailored for `elm-mdl` specific use.

@docs Config, defaultConfig, plug, plugger, install
@docs add

-}

import Json.Decode as Json
import Html.Events
import Html
import Task


-- CONFIG

{-| Dispatch configuration type
 -}
type Config m =
  Config
    { decoders : List (String, (Json.Decoder m, Maybe Html.Events.Options))
    , lift : Maybe (List m -> m)
    , lift : Maybe ((List m) -> m)
    }


{-| Empty configuration
 -}
defaultConfig : Config m
defaultConfig =
  Config
    { decoders = []
    , lift = Nothing
    }


{-| This function tells Dispatch how to convert a list of messages to a single
message; how to _plug_ itself into your TEA component.
 -}
plug : (List m -> m) -> Config m -> Config m
plug f (Config config) =
  Config { config | lift = Just f }


{-| Get the Dispatch lifting function
-}
plugger : Config m -> Maybe (List m -> m)
plugger (Config config) =
  config.lift


{-| Add an event-handler to the current configuration
 -}
add : String -> Maybe Html.Events.Options -> Json.Decoder msg -> Config msg -> Config msg
add event options decoder (Config config) =
  Config
    { config | decoders = (event, (decoder, options)) :: config.decoders }


{-| This function returns a list of `Html.Attribute` containing handlers that
will allow for dispatching of multiple decoders from a single `Html.Event`
Construct event handlers for the given configuration
 -}
install : Config msg -> List (Html.Attribute msg)
install (Config config) =
  case config.lift of
    Just f ->
      List.map (onMany f) (group config.decoders)
    Nothing ->
      List.map onSingle config.decoders


{-| Promote `msg` to `Cmd msg`
-}
cmd : msg -> Cmd msg
cmd msg =
  Task.perform (always msg) (always msg) (Task.succeed msg)


-- UPDATE


{-| Maps messages to commands
-}
forward : (List m) -> Cmd m
forward messages =
  List.map cmd messages |> Cmd.batch


{-| Map the second element of a tuple

    map2nd ((+) 1) ("bar", 3) == ("bar", 4)
-}
map2nd : (b -> c) -> ( a, b ) -> ( a, c )
map2nd f ( x, y ) =
  ( x, f y )


update1 : (m -> model -> (model, d)) -> m -> ( model, List d ) -> ( model, List d )
update1 update cmd ( m, gs ) =
  update cmd m
    |> map2nd (flip (::) gs)


{-| Runs the given `update` on all the messages and
returns the updated model including batching of
any commands returned by running the `update`.
-}
update : (msg -> model -> (model, Cmd obs)) -> (List msg) -> model -> (model, Cmd obs)
update update msg model =
  List.foldl (update1 update) (model, []) msg
    |> map2nd Cmd.batch


-- VIEW


decode : List (Json.Decoder m) -> Json.Value -> Result c (List m)
decode decoders v0 =
  List.filterMap (flip Json.decodeValue v0 >> Result.toMaybe) decoders
    |> Result.Ok


{-| Applies given decoders to the same initial value
   and return the applied results as a list
-}
flatten : List (Json.Decoder m) -> Json.Decoder (List m)
flatten =
  decode >> Json.customDecoder Json.value


{-| Dispatch multiple decoders for a single event.

Returns `Nothing` if an empty list of decoders is provided.
Otherwise returns `Just Html.Attribute` with a listener
that will attempt to run multiple decoders on the event.
 -}
on
  : String
  -> (List m -> m)
  -> List (Json.Decoder m)
  -> Html.Attribute m
on event lift =
  onWithOptions event lift Html.Events.defaultOptions


{-| Dispatch multiple decoders for a single event.
Options apply to the whole event.

Returns `Nothing` if an empty list of decoders is provided.
Otherwise returns `Just Html.Attribute` with a listener
that will attempt to run multiple decoders on the event.
Options apply to all decoders.

 -}
onWithOptions
  : String
  -> (List m -> m)
  -> Html.Events.Options
  -> List (Json.Decoder m)
  -> Html.Attribute m
onWithOptions event lift options decoders =
  flatten decoders
    |> Json.map lift
    |> Html.Events.onWithOptions event options


{-| Run multiple decoders on a single Html Event with
the given options
-}
onMany
  : (List m -> m)
  -> ( String, List ( Json.Decoder m, Maybe Html.Events.Options ) )
  -> Html.Attribute m
onMany lift decoders =
  case decoders of
    -- Install direct handler for singleton case
    (event, [ decoder ])  ->
      onSingle (event, decoder)

    (event, decoders) ->
      onWithOptions event lift (pickOptions decoders) (List.map fst decoders)


pickOptions : List ( a, Maybe Html.Events.Options ) -> Html.Events.Options
pickOptions decoders =
  case decoders of
    (_, Just options) :: _ -> options
    _ :: rest -> pickOptions rest
    [] -> Html.Events.defaultOptions


onSingle
    : (String, (Json.Decoder m, Maybe Html.Events.Options ))
    -> Html.Attribute m
onSingle (event, (decoder, option)) =
  Html.Events.onWithOptions
    event
      (Maybe.withDefault Html.Events.defaultOptions option)
      decoder


-- UTILITIES


{-| Group a list of pairs based on the first item. Optimised for lists of size
< 10 with < 3 overlaps.
-}
group : List ( a, b ) -> List ( a, List b )
group =
  group' []


split :
  a
  -> List b
  -> List ( a, b )
  -> List ( a, b )
  -> ( List b, List ( a, b ) )
split k0 same differ xs =
  case xs of
    [] ->
      ( same, differ )

    (( k, v ) as x) :: xs ->
      if k == k0 then
        split k0 (v :: same) differ xs
      else
        split k0 same (x :: differ) xs


group' : List ( a, List b ) -> List ( a, b ) -> List ( a, List b )
group' acc items =
  case items of
    [] ->
      acc

    [ ( k, v ) ] ->
      ( k, [ v ] ) :: acc

    [ ( k1, v1 ), ( k2, v2 ) ] ->
      if k1 == k2 then
        ( k1, [ v2, v1 ] ) :: acc
      else
        ( k2, [ v2 ] ) :: ( k1, [ v1 ] ) :: acc

    ( k, v ) :: xs ->
      let
        ( same, different ) =
          split k [ v ] [] xs
      in
        group' (( k, same ) :: acc) different