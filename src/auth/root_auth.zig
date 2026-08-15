//! Root file for module related to authorization
//! Here, authorization refers to the backend storage of credentials.
//!
//! The config module is used to build and parse a config.zap. But
//! configuration ends at parsing users allowed in the config.zap. Handling
//! cookies, checking if a credential pair is valid, etc - that falls within
//! the scope of this module. (Of course, this module may change as more about
//! security is learned)

//Beginning Necessary Imports
const std = @import("std");

//Creating a struct that will represent the data we'll store in the backend
//related to a credential
//
//  Clarifying the two references to time:
//     configured timeout is a value that allows the config.zap to set different
//     cookie expiration times for different users. Example, Person A tends to
//     lose their phone or leave it around unlocked? they can be assigned a
//     shorter timeout due to their inherit security risk as compared to Person B
//     who may have such a long expiry time that their cookies are considered
//     lifetime valid. 
//  
//     Expiry time is the value calculated upon cookie creation for when that
//     cookie will no longer register
const UserCredential = struct {
    username : []const u8,
    password : []const u8,
    configured_timeout : i64, //The amount of time that user's cookie is
                              //allowed to be valid for
    cookie : ?[]const u8 = null,
    expiry_time : i64 = 0, //The realtime the cookie expires
};

//Creating a runtime array list that will hold credentials to avoid having to
//repetively parse the config.zap.
pub var VALUE_USER_CREDENTIALS : std.ArrayList(UserCredential) = .empty;


//******************************************************************************
//************ Begin Functions for handling/accessing credentials **************
//******************************************************************************


//******************************************************************************
//* Function:    freeAllocations
//*
//* Description: At this point, credentials are parsed on startup and saved into
//               an arraylist. Because we cannot know how many credentials will
//               be configured in a running system, the credentials that are
//               strings had to be allocated on startup. This is a function
//               that can be run at the termination of the program to prevent
//               these allocations from being a heap leak.
//******************************************************************************
pub fn freeAllocations(allocator : std.mem.Allocator) void {
    for (VALUE_USER_CREDENTIALS.items) |entry| {
        allocator.free(entry.username);
        allocator.free(entry.password);
        if (entry.cookie) |cookie| {
            allocator.free(cookie);
        }
    }
    VALUE_USER_CREDENTIALS.deinit(allocator);
}


//******************************************************************************
//* Function:    check_user_credential
//*
//* Description: This is a function used to check if a username/password pair is
//               present in the authorized list of users.
//
//               This function does not fail - just returns false unless perfect
//               match is found.
//******************************************************************************
pub fn check_user_credential(username : []const u8, password : []const u8) bool {
    for (VALUE_USER_CREDENTIALS.items) |valid_credential| {
        if (std.mem.eql(u8, valid_credential.username, username)) {
            if (std.mem.eql(u8, valid_credential.password, password)) {
                return true;
            }
            else {
                return false;
            }
        }
    }
    return false;
}


//******************************************************************************
//* Function:    update_user_cookie
//*
//* Description: This function is used to update the credential arraylist with 
//               a new cookie for a user. This should only be run after the user
//               has been authenticated. (Note it only checks for username).
//
//               The two key things that this function does is update the user's
//               cookie string in the master list. But, this function also
//               captures the current time and updates that entry's expiry_time
//******************************************************************************
pub fn update_user_cookie(io : std.Io, username : []const u8, cookie : []const u8) !void {
    const timestamp_now = std.Io.Timestamp.now(io, .real);
    const now_seconds = timestamp_now.toSeconds();
    for (VALUE_USER_CREDENTIALS.items) |*cred| {
        if (std.mem.eql(u8, cred.username, username)) {
            cred.cookie = cookie;
            cred.expiry_time = cred.configured_timeout + now_seconds;
            return;
        }
    }
    return error.UserNotFound;
}


//******************************************************************************
//* Function:    is_valid_cookie
//*
//* Description: This function is used when evaluating a stream early in the 
//               process. This function assumes that there is a cookie present
//               in the stream, and that that value has already been parsed
//               out. Then, this function can be used by submitting the parsed
//               cookie. This function checks said cookie against all entries
//               in the arraylist of supported credentials to make sure that that
//               cookie is one that it remembers having issued previously.
//******************************************************************************
pub fn is_valid_cookie(cookie : []const u8) bool {
    for (VALUE_USER_CREDENTIALS.items) |cred| {
        const credential_cookie = cred.cookie orelse continue;
        if (std.mem.eql(u8, credential_cookie, cookie)) {
            return true;
        }
    }
    return false;
}


//******************************************************************************
//* Function:    cookie_expiry_time
//*
//* Description: This function is used for getting the master/arraylist expiry
//               time for a provided cookie. 
//
//               Original intention of this function is to take a parsed cookie
//               from a stream. Then, when deciding to allow the request, the 
//               value returned by this function can be compared against a new
//               timestamp to choose to redirect the client to having to login 
//               again.
//
//               (The big thing I found was that you cannot rely on the client
//                to stop sending cookies immediately once the expiry time hits
//                client side. Almost as if there is some cleanup loop that is
//                not frequently run. So server side management of expiry time
//                is essentialy if config is such to have short lived cookies)
//******************************************************************************
pub fn cookie_expiry_time(
    cookie : []const u8,
) ?i64 {
    for (VALUE_USER_CREDENTIALS.items) |cred| {
        const credential_cookie = cred.cookie orelse continue;
        if (std.mem.eql(u8, credential_cookie, cookie)) {
            return cred.expiry_time;
        }
    }
    return null;
}
