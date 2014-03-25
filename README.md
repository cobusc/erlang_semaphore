semaphore
=========

Semaphore is an Erlang library providing functionality similar to that of POSIX semaphores.

To start a semaphore:

```erlang
semaphore:start_link(sem_name, 2).
```

A blocking call to the semaphore:

```erlang
semaphore:wait(sem_name).
```

A non-blocking call to the semaphore:

```erlang
semaphore:try_wait(sem_name).
```

A blocking call to the semaphore, with a specified timeout;

```erlang
semaphore:timed_wait(sem_name, 1000).
```

Releasing the semaphore:

```erlang
semaphore:post(sem_name).
```

