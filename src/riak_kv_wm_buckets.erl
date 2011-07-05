%% -------------------------------------------------------------------
%%
%% riak_kv_wm_buckets - Webmachine resource for listing buckets.
%%
%% Copyright (c) 2007-2011 Basho Technologies, Inc.  All Rights Reserved.
%%
%% This file is provided to you under the Apache License,
%% Version 2.0 (the "License"); you may not use this file
%% except in compliance with the License.  You may obtain
%% a copy of the License at
%%
%%   http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing,
%% software distributed under the License is distributed on an
%% "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
%% KIND, either express or implied.  See the License for the
%% specific language governing permissions and limitations
%% under the License.
%%
%% -------------------------------------------------------------------

%% @doc Resource for listing Riak buckets over HTTP.
%%
%% Available operations:
%%
%% GET /buckets?buckets=true (NEW) 
%% GET /Prefix?buckets=true
%%   Get information about available buckets. Note that generating the
%%   bucket list is expensive, so we require the "buckets=true" arg.

-module(riak_kv_wm_buckets).

%% webmachine resource exports
-export([
         init/1,
         service_available/2,
         content_types_provided/2,
         encodings_provided/2,
         produce_bucket_list/2
        ]).

-import(riak_kv_wm_utils, 
        [
         get_riak_client/2,
         get_client_id/1,
         default_encodings/0,
         add_bucket_link/3
        ]).

%% @type context() = term()
-record(ctx, {
          client,       %% riak_client() - the store client
          prefix,       %% string() - prefix for resource uris
          riak,         %% local | {node(), atom()} - params for riak client
          method        %% atom() - HTTP method for the request
         }).

-include_lib("webmachine/include/webmachine.hrl").
-include("riak_kv_wm_raw.hrl").

%% @spec init(proplist()) -> {ok, context()}
%% @doc Initialize this resource.  This function extracts the
%%      'prefix' and 'riak' properties from the dispatch args.
init(Props) ->
    {ok, #ctx{
       prefix=proplists:get_value(prefix, Props),
       riak=proplists:get_value(riak, Props)
      }}.


%% @spec service_available(reqdata(), context()) ->
%%          {boolean(), reqdata(), context()}
%% @doc Determine whether or not a connection to Riak
%%      can be established.  This function also takes this
%%      opportunity to extract the 'bucket' and 'key' path
%%      bindings from the dispatch, as well as any vtag
%%      query parameter.
service_available(RD, Ctx=#ctx{riak=RiakProps}) ->
    case get_riak_client(RiakProps, get_client_id(RD)) of
        {ok, C} ->
            {true, 
             RD,
             Ctx#ctx{ 
               method=wrq:method(RD),
               client=C
              }};
        Error ->
            {false,
             wrq:set_resp_body(
               io_lib:format("Unable to connect to Riak: ~p~n", [Error]),
               wrq:set_resp_header(?HEAD_CTYPE, "text/plain", RD)),
             Ctx}
    end.


%% @spec content_types_provided(reqdata(), context()) ->
%%          {[{ContentType::string(), Producer::atom()}], reqdata(), context()}
%% @doc List the content types available for representing this resource.
%%      "application/json" is the content-type for bucket lists.
content_types_provided(RD, Ctx) ->
    {[{"application/json", produce_bucket_list}], RD, Ctx}.


%% @spec encodings_provided(reqdata(), context()) ->
%%          {[{Encoding::string(), Producer::function()}], reqdata(), context()}
%% @doc List the encodings available for representing this resource.
%%      "identity" and "gzip" are available for bucket lists.
encodings_provided(RD, Ctx) ->
    {default_encodings(), RD, Ctx}.


%% @spec produce_bucket_list(reqdata(), context()) -> {binary(), reqdata(), context()}
%% @doc Produce the JSON response to a bucket-level GET.
%%      Includes a list of known buckets if the "buckets=true" query
%%      param is specified.
produce_bucket_list(RD, Ctx=#ctx{client=C}) ->
    {ListPart, LinkRD} =
        case wrq:get_qs_value(?Q_BUCKETS, RD) of
            ?Q_TRUE ->
                {ok, Buckets} = C:list_buckets(),
                {[{?JSON_BUCKETS, Buckets}],
                 lists:foldl(fun(B, Acc) -> add_bucket_link(B,Acc,Ctx#ctx.prefix) end,
                             RD, Buckets)};
            _ ->
                {[], RD}
        end,
    {mochijson2:encode({struct, ListPart}), LinkRD, Ctx}.
