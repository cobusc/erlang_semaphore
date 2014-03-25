[![Build Status](https://travis-ci.org/cobusc/erlang_semaphore.png?branch=master)](https://www.travis-ci.org/cobusc/erlang_semaphore)

semaphore
=========

Semaphore is an Erlang library providing functionality similar to that of POSIX semaphores.

Creating the semaphore
----------------------

To create a semaphore named `sem_name` with a value of `2`, use:

```erlang
semaphore:start_link(sem_name, 2).
```

Semaphore functions
-------------------

### wait

This call blocks until the semaphore becomes available. It will always return `ok` and is equivalent
to calling `semaphore:timed_wait(sem_name, infinity)`.

Example: 

```erlang
semaphore:wait(sem_name).
```

### try_wait

This is a non-blocking call to the semaphore. It will immediately return either `ok` if the semaphore was
acquired, or `error` if not.

Eaxmple:

```erlang
semaphore:try_wait(sem_name).
```

### timed_wait

This call blocks until either the semaphore becomes available or the specified timeout (in milliseconds) is reached.
It returns `ok` if the semaphore was acuired, or `{error, timeout}` if the timeout was reached.

```erlang
semaphore:timed_wait(sem_name, 1000).
```

### post

This call releases the semaphore. It returns `ok` if successful and `error` if the calling process did not acquire the semaphore.

```erlang
semaphore:post(sem_name).
```

### get_value

This call returns the current value of the semaphore.

```erlang
semaphore:get_value(sem_name).
```

