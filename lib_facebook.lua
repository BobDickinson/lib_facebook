--====================================================================--
-- Module: lib_facebook   
-- 
--    Copyright (C) 2012 Triple Dog Dare Games, Inc.  All Rights Reserved.
--
-- License:
--
--    Permission is hereby granted, free of charge, to any person obtaining a copy of 
--    this software and associated documentation files (the "Software"), to deal in the 
--    Software without restriction, including without limitation the rights to use, copy, 
--    modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, 
--    and to permit persons to whom the Software is furnished to do so, subject to the 
--    following conditions:
-- 
--    The above copyright notice and this permission notice shall be included in all copies 
--    or substantial portions of the Software.
-- 
--    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, 
--    INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR 
--    PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE 
--    FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR 
--    OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER 
--    DEALINGS IN THE SOFTWARE.
--
-- Overview:
--
--    This library creates a wrapper around the Corona SDK Facebook API support.
--    Using this library will streamline your Facebook client logic and make it 
--    easier to debug and to catch/handle errors.  Features include:
--
--    * Support for testing of Facebook API calls from the Corona simulator.
--
--    * Detailed debug logging of all method call and protocol data, specific to 
--      the method/API being called (can be enabled/disabled with a flag).
--
--    * Ability to specify a listener for each individual Facebook API call
--      instance, if desired.
--
--    * Facebook API request state (method, path, and params) provided to the
--      response listener.
--
--    * Flood protection (new API call not allowed until previous call completed).
--
--    * Tracking of login state, plus error handling for API calls made when not
--      logged in.
--
--    * Automatic decoding of Facebook API JSON responses, with error checking.
--
--    * Consolidation of error indication and error details (for both call/connection
--      errors and protocol errors).
--
-- Module Settings:
--
--    libFacebook.isDebug
--
--    libFacebook.FB_App_ID (must be set by caller)
--
--    libFacebook.FB_Access_Token (must also be set by caller for use in simulator)
--
-- Module Methods:
--
--    libFacebook.isLoggedIn( )
--
--    libFacebook.login( permissions, onLoginComplete )
--
--    libFacebook.request( path, httpMethod, params, onRequestComplete )
--
--    libFacebook.showDialog( params, onDialogComplete )
--
--    libFacebook.logout( onLogoutComplete )
--
-- Usage:
--
--    local libFacebook = require("lib_facebook")
--    libFacebook.FB_App_ID = "your_app_id"
--    libFacebook.isDebug = true
--
--    local function onRequestComplete( event )
--        if event.isError then
--            print("Facebook request error: " .. event.response.error.message)
--        else
--            -- Success - process my friends list
--            print("Friends list fetched with request: " .. event.request.path)
--            for _, friend in pairs(event.response.data) do
--                 print("  Facebook friend: " .. friend.name .. ", id: " .. friend.id)
--            end
--        end
--    end
--
--    local function onLoginComplete( event )
--        if event.phase ~= "login" then
--            print("Facebook login not successful")
--        elseif event.isError then
--            print("Facebook login error, details: " .. event.response.error.message)
--        else
--            -- Successfully logged in, now list my friends
--            libFacebook.request("me/friends", "GET", {limit = "10"}, onRequestComplete)
--        end
--    end
--
--    libFacebook.login({"publish_stream"}, onLoginComplete)
--
-- Simulator support
--
--    For Windows/Mac simulator testing go to the Facebook Graph API Eplorer:
--
--      http://developers.facebook.com/tools/explorer
--
--    Set "Application" to your app.  Select "Get Access Token" (choose appropriate
--    permissions).  Use the supplied access token as the value for FB_Access_Token
--    (exported from this module, and which should be set by the calling module). 
--    Note that this token will time out and you will need to repeat this action for
--    each testing session (normal access tokens expire after two hours).
--
--    Known limitations under simulator:
--
--      No support for facebook.showDialog( )
--      No file upload support
--      No actual authentication (login/logout stubbed out)
--
--====================================================================--
--
local M = {}

local facebook = require("facebook")
local json = require("json")
local url = require("socket.url")

-- This should be set outside of this module, by the user of the module
M.FB_App_ID = "_UNDEFINED_"

-- This should also be set for testing using the simulator (see above instructions)
M.FB_Access_Token = nil

-------------------------------------------------------------------------------
-- Debug logging support
--
M.isDebug = true

local dbgPrefix = "[Facebook]"

local function dbg( ... )
    if M.isDebug then
        print(dbgPrefix .. " " .. unpack(arg))
    end
end

local function dbgf( ... )
    if M.isDebug then
        dbg(string.format(unpack(arg)))
    end
end

local function dbgTable( t, label, level )
    if M.isDebug then
        if label then dbg(label) end
        level = level or 0

        if t then
            for k,v in pairs(t) do
                local prefix = ""
                for i=1,level do
                    prefix = prefix .. "    "
                end

                dbg(prefix .. "[" .. tostring(k) .. "] = " .. tostring(v))
                if type(v) == "table" then
                    dbg(prefix .. "{")
                    dbgTable(v, nil, level + 1)
                    dbg(prefix .. "}")
                end
            end
        end
    end
end

local function dbgDumpFacebookRequestResponse( request, event )
    if M.isDebug then
        dbg("----- Begin response -----")
        if request then
            -- Dump request
            if request.path == "login" then
                dbgf("Request: login")
                for i = 1, #request.params do
                    dbgf("Request permission: %s", request.params[i])
                end
            else
                if request.method then
                    dbgf("Request: %s %s", request.method, request.path)
                else
                    dbgf("Request: %s", request.path)
                end
                if request.params then
                    for key, value in pairs(request.params) do
                        dbgf("Request parameter - %s: %s", key, value)
                    end
                end
            end
        end
        
        if event then
            -- Dump response
            dbg("Response - event.name: " .. event.name)
            dbg("Response - event.type: " .. event.type)
            if event.phase then
                dbg("Response - event.phase: " .. event.phase)
            end
            if event.token then
                dbg("Response - access token: " .. tostring(event.token))
            end
            if event.type == "dialog" then
               dbg("Response - dialog 'didComplete' was: " .. tostring(event.didComplete))
            end
            if event.isError then
               dbg("Response reports 'isError'")
            end
            if event.response then
                if type(event.response) == "table" then
                    dbgTable(event.response, "Response body table:")
                else
                    local errorMsg = tostring(event.response)
                    if errorMsg and errorMsg:len() > 0 then
                        dbg("Response body (" .. type(event.response) .. "): " ..  errorMsg)
                    end
                end                    
            end
        end
        dbg("----- End response -----")
    end
end
--
-------------------------------------------------------------------------------

local fbLoggedIn = false

-- Current request being processed (next response to be handled below)
--
local fbNextRequest = nil
local function setNextRequest( path, httpMethod, params, onRequestComplete )
    fbNextRequest = {
        path = path,
        method = httpMethod,
        params = params,
        listener = onRequestComplete,
    }
end

-- listener for all "fbconnect" events
--
local function fbListener( event )

    -- Response event attributes:
    --
    --   event.name is "fbconnect"
    --   event.type is one of: "session" or "request" or "dialog"
    --   [For event.type "session"]
    --       event.phase is one of: "login", "loginFailed", "loginCancelled", "logout"
    --       [For event.phase "login"]
    --           event.token is the access token for the session
    --   [For event.type "dialog"]
    --       event.didComplete is false if dialog did not complete (user cancelled)
    --   event.isError is true if request failed (network failure)
    --   event.response is either an error string (if isError) or a json encoded response

    -- Do some pre-processing of the response
    --    
    if event.isError then
        -- This is a local (API call or connection) error.  We are going to convert it into the
        -- same kind of error structure that a Graph API error produces to make it easier for the
        -- listener to handle all errors in a uniform way.
        local error_message = "Unknown Error"
        if event.response and type(event.response) == "string" and event.response:len() > 0 then
            error_message = event.response
        end
        
        local error_response = {}
        error_response["message"] = error_message
        error_response["type"]    = "CallError"
        error_response["code"]    = -1
        
        event.response_raw = event.response
        event.response = {}
        event.response["error"] = error_response
    else
        if event.response and event.response:len() > 0 then
            event.response_raw = event.response
            if event.response_raw:sub(1,1) == "{" then
                -- event.response is a JSON object from the FB server - decode it for convenience
                event.response = json.decode(event.response_raw)
            end
            if event.response["error"] then
                -- This is a Graph API error response.  We set isError to make it easier for the
                -- listener to detect all errors in a uniform way.
                event.isError = true
            end
        end

        -- Track logged-in state.  We check isError again here, because it could have gotten set
        -- above in the case of a Graph API error.
        --
        if not event.isError then 
            if event.type == "session" then
                -- Track login state
                if event.phase == "login" then 
                    fbLoggedIn = true
                elseif event.phase == "logout" then 
                    fbLoggedIn = false
                end
            end
        end
    end
    
    dbgDumpFacebookRequestResponse(fbNextRequest, event)
    
    if fbNextRequest == nil then
        error("Facebook request completed, but no pending request state was available")
    else
        -- Call the supplied listener
        event.request = fbNextRequest
        fbNextRequest = nil
        event.request.listener(event)
    end
end

------------------------------------------------------------------------------------
-- Simulator support methods
--
local isSimulator = ("simulator" == system.getInfo("environment"))

local function simulatorLogin( )
    local fbEvent = { }
    fbEvent["name"]  = "fbconnect"
    fbEvent["type"]  = "session"
    fbEvent["phase"] = "login"
    fbEvent["token"] = M.FB_Access_Token
    fbListener(fbEvent)
end

local function simulatorRequest( path, httpMethod, params )

    local params = params or {}
    if M.FB_Access_Token then
        params["access_token"] = M.FB_Access_Token
    else
        error("Facebook functionality in the simulator requires that FB_Access_Token be set in lib_facebook.lua")
    end

    -- Build request and submit using network.request

    local queryString
    for k, v in pairs(params) do
        if queryString then
            queryString = queryString .. "&"
        else
            queryString = "?"            
        end
        queryString = queryString .. k .. "=" .. url.escape(v)
    end

    local url = "https://graph.facebook.com/" .. path .. queryString
    dbg("Simulator Facebook request: " .. url)
    
    local function onRequestComplete( event )
        local fbEvent = { }
        fbEvent["name"]     = "fbconnect"
        fbEvent["type"]     = "request"
        fbEvent["isError"]  = event.isError
        fbEvent["response"] = event.response
        fbListener(fbEvent)
    end
    
    network.request(url, httpMethod, onRequestComplete)
end

local function simulatorLogout( )
    local fbEvent = { }
    fbEvent["name"]  = "fbconnect"
    fbEvent["type"]  = "session"
    fbEvent["phase"] = "logout"
    fbListener(fbEvent)
end

------------------------------------------------------------------------------------
-- For all listeners used below:
------------------------------------------------------------------------------------
--
-- local function onXxxxxxComplete( event )
--
-- The request parameters cooresponding to the request are provided to the listener
-- in event.request, as follows:
--
--     event.request.path
--     event.request.method
--     event.request.params
--
-- The error state and response are provided as follows:
--
--     event.isError         - true if an error occurred (see below)
--     event.response        - The decoded response table
--     event.response_raw    - The raw response
--
-- If event.isError, then event.response.error contains the error details table.  
-- This is consistent for both call/connection errors and Graph API errors.  The 
-- details provided include:
--
--     event.response.error.message - The error message
--     event.response.error.type    - The error type for Graph API errors, or "CallError"
--     event.response.error.code    - The error code, or -1 if not known
--
-- If there is no error, then event.response contains a table with response data 
-- from the facebook Graph API request.
--
-- The raw data returned from the Facebook call can be found in event.response_raw.
-- This may contain an error message string, in the case of call/connection errors,
-- or an undecoded JSON string in the case of a completed Graph API request.
--
------------------------------------------------------------------------------------

------------------------------------------------------------------------------------
-- libFacebook.isLoggedIn( )
--
function M.isLoggedIn( )
    return fbLoggedIn
end

------------------------------------------------------------------------------------
-- libFacebook.login( permissions, onLoginComplete )
--
--   permissions - see http://developers.facebook.com/docs/reference/api/permissions/
--
--   onLoginComplete - function onLoginComplete( event )
--
--     event.name        - "fbconnect"
--     event.type        - "session"
--     event.phase       - One of: "login", "loginFailed", "loginCancelled"
--     event.token       - The access token for the session
--     event.isError     - true if an error occurred, error in event.response
--     event.response    - If error, the error details
--
-- Usage:
--
--   local libFacebook = require("lib_facebook")
--   libFacebook.FB_App_ID = "your_app_id"
--
--   local function onLoginComplete( event )
--       if event.phase ~= "login" then
--           print("Facebook login not successful")
--       elseif event.isError then
--           print("Facebook login error: " .. event.response.error.message)
--       else
--           -- Success - Now you can make Facebook requests!
--       end
--   end
--
--   libFacebook.login({"publish_stream"}, onLoginComplete)
--
function M.login( permissions, onLoginComplete )
    dbg("Preparing to log in")

    assert(M.FB_App_ID and (M.FB_App_ID:len() > 0) and (M.FB_App_ID ~= "_UNDEFINED_"), "Facebook FB_App_ID not defined by caller")
    
    setNextRequest("login", nil, permissions, onLoginComplete)
    
    if isSimulator then
        simulatorLogin()
    else
        facebook.login(M.FB_App_ID, fbListener, permissions)
    end
end

------------------------------------------------------------------------------------
-- libFacebook.request( path, httpMethod, params, onRequestComplete )
--
--   onRequestComplete - function onRequestComplete( event )
--
--     event.name        - "fbconnect"
--     event.type        - "request"
--     event.isError     - true if an error occurred, error in event.response
--     event.response    - The decoded response table
--
-- Usage:
--
--   local function onRequestComplete( event )
--       if event.isError then
--           print("Facebook request error: " .. event.response.error.message)
--       else
--           -- Success - process event.response here!
--       end
--   end
--
--   libFacebook.request("me/friends", "GET", {fields = "name", limit = "10"}, onRequestComplete)
--
function M.request( path, httpMethod, params, onRequestComplete )
    dbg("Preparing to send request: " .. httpMethod .. " " .. path)

    if fbNextRequest ~= nil then
        error("Error processing Facebook request: " .. httpMethod .. " " .. path .. ", a previous request is still being processed")
    else
        setNextRequest(path, httpMethod, params, onRequestComplete)
    end
    
    if not fbLoggedIn then
        error("Error processing Facebook request: " .. httpMethod .. " " .. path .. ", not currently logged in")
    else
        if isSimulator then
            simulatorRequest(path, httpMethod, params)
        else
            facebook.request(path, httpMethod, params)
        end
    end
end

------------------------------------------------------------------------------------
-- libFacebook.showDialog( param, onDialogComplete )
--
--   onDialogComplete - function onDialogComplete( event )
--
--     event.name        - "fbconnect"
--     event.type        - "dialog"
--     event.didComplete - Is false if dialog did not complete (user cancelled)
--     event.isError     - true if an error occurred, error in event.response
--     event.response    - The decoded response table
--
function M.showDialog( params, onDialogComplete )
    dbg("Preparing to show dialog")

    if fbNextRequest ~= nil then
        error("Error processing Facebook show dialog, a previous request is still being processed")
    else
        setNextRequest("showdialog", nil, params, onDialogComplete)
    end
    
    if not fbLoggedIn then
        error("Error processing Facebook show dialog, not currently logged in")
    else
        if isSimulator then
            error("Facebook showDialog not supported in simulator")
        else
            facebook.showDialog(params)
        end
    end
end

------------------------------------------------------------------------------------
-- libFacebook.logout( onLogoutComplete )
--
--   onLogoutComplete - function onLogoutComplete( event )
--
--     event.name        - "fbconnect"
--     event.type        - "session"
--     event.phase       - "logout"
--     event.isError     - true if an error occurred, error in event.response
--     event.response    - If error, the error details
--
-- Usage:
--
--   local function onLogoutComplete( event )
--       if event.isError then
--           print("Facebook error logging out: " .. event.response.error.message)
--       else
--           -- Success - You are now logged out!
--       end
--   end
--
--   libFacebook.logout(onLogoutComplete)
--
function M.logout( onLogoutComplete )
    dbg("Preparing to log out")

    if fbNextRequest ~= nil then
        error("Error processing Facebook logout, a previous request is still being processed")
    else
        setNextRequest("logout", nil, nil, onLogoutComplete)
    end

    if not fbLoggedIn then
        error("Error processing Facebook logout, not currently logged in")
    else
        if isSimulator then
            simulatorLogout()
        else
            facebook.logout()
        end
    end
end

return M
