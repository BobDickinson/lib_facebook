-------------------------------------------------------------------------------
-- Sample/test usage for lib_facebook
--
local libFacebook = require("lib_facebook")
libFacebook.FB_App_ID = ""        -- You must supply this value
libFacebook.FB_Access_Token = nil -- You must supply this value to test from the simulator

local function onListFriendsComplete( event )
    if event.isError then
        print("List Friends - Error, details: " .. event.response.error.message)
    else
        -- This is a list of my friends, with an indicator of whether they have
        -- this app installed.  Let's see who's cool...
        for _, friend in pairs(event.response.data) do
            print("Facebook friend: " .. friend.name .. ", id: " .. friend.id)
            if friend.installed then
                print(" - has this app installed!")
            end
        end
    end
end

local function onListMeComplete( event )
    if event.isError then
        print("List Me - Error, details: " .. event.response.error.message)
    else
        -- This is me...
        print("Me: " .. event.response.name .. ", id: " .. event.response.id)
        
        -- Go get the first 10 friends from my friend list, and let me know if any
        -- of them have this app installed...
        libFacebook.request("me/friends", "GET", {fields = "name,installed", limit = 10,}, onListFriendsComplete )
    end
end

local function onLoginComplete( event )
    if event.phase ~= "login" then
        print("Facebook login not successful")
    elseif event.isError then
        print("Facebook login error - details: " .. event.response.error.message)
    else
        -- Login succeeded, find out who I am...
        libFacebook.request("me", "GET", {fields = "name"}, onListMeComplete )
    end
end

libFacebook.login({"publish_stream"}, onLoginComplete)
