# List of Tasks To Implement
- Establish better identity management
- Add nullable status to ComplexStream
- Make connections more secure for human clients

# Task Details

## Establish better identity management

I need some method of handling certificates or something that will allow for camera's to authenticate themselves differently from a user. I have an ongoing grok thread trying to learn about the implementaitons of CA certificates. This is the most promising solution at this point.

## Add nullable status to ComplexStream

Right now in the connectionThread, there is a `defer` statement to make sure the stream is getting closed. I like this as a security method and as a ultimate point where the stream is closed. 

However, I don't want clients to be stuck in a position where they hang due to not getting a status message back. 

I think this can be solved by making a status attribute to the struct. I can also make it null by default. Then, I can say that if the status is null when I'm going to close - than I've not sent any response for any number of reasons. 

This null check could then be used to indicate some sort of server error. While this wouldn't be useful to the client - it would give them certainty and not leave their browser spinning and waiting for content. 

In some testing so far - I'm seeing these moments of hanging - but I've not taken note about why that's been happening. (It could be due to other things like improperly reading from the stream)

## Make connections more secure for human clients
