//! This module is reserved for tracking and managing the list of clients that
//! are connected. But, why would it be important to track the clients?
//!
//! Simply put, if the server is going to be a hub for distributing settings to
//! the cameras, the server is going to be best served by attempting to have a
//! ledger of the clients. But why? What if the user is configuring a client
//! that is rarely connecting to upload (the camera/client is recording
//! property that is less critical for archiving and wants to upload less
//! frequently to save bandwidth for the more important nodes - how would the
//! server know to reach out to a specific client without knowing the IP
//! address to write to)
//!
//! This module is specific to the operations related to this tangent of
//! functionality.


//############################## Begin Imports #################################



const std = @import("std");



//############################# Begin Functions ################################
