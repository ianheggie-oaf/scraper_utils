Fibers and Threads
==================

This sequence diagram supplements the notes on the {ScraperUtils::Scheduler} class and is intended to help show
the passing of messages and control between the fibers and threads.

* To keep things simple I have only shown the Fibers and Threads and not all the other calls like to the
  OperationRegistry to lookup the current operation, or OperationWorker etc.
* There is ONE (global) response queue, which is monitored by the Scheduler.run_operations loop in the main Fiber
* Each authority has ONE OperationWorker (not shown), which has ONE Fiber, ONE Thread, ONE request queue.
* I use "◀─▶" to indicate a call and response, and "║" for which fiber / object is currently running.

```text

SCHEDULER (Main Fiber)      
NxRegister-operation  RESPONSE.Q   
   ║──creates────────◀─▶┐
   ║                    │       FIBER (runs block passed to register_operation)
   ║──creates──────────────────◀─▶┐         WORKER object and Registry
   ║──registers(fiber)───────────────────────▶┐           REQUEST-Q
   │                    │         │           ║──creates─◀─▶┐       THREAD
   │                    │         │           ║──creates───────────◀─▶┐
   ║◀─────────────────────────────────────────┘             ║◀──pop───║ ...[block waiting for request]
   ║                    │         │           │             ║         │
run_operations          │         │           │             ║         │
   ║──pop(non block)─◀─▶│         │           │             ║         │ ...[no responses yet]
   ║                    │         │           │             ║         │
   ║───resumes-next─"can_resume"─────────────▶┐             ║         │
   │                    │         │           ║             ║         │
   │                    │         ║◀──resume──┘             ║         │ ...[first Resume passes true]
   │                    │         ║           │             ║         │ ...[initialise scraper]
```
**REPEATS FROM HERE**  
```text
 SCHEDULER        RESPONSE.Q    FIBER       WORKER        REQUEST.Q THREAD
   │                    │         ║──request─▶┐             ║         │
   │                    │         │           ║──push req ─▶║         │
   │                    │         ║◀──────────┘             ║──req───▶║
   ║◀──yields control─(waiting)───┘           │             │         ║ 
   ║                    │         │           │             │         ║ ...[Executes network I/O request]
   ║                    │         │           │             │         ║
   ║───other-resumes... │         │           │             │         ║ ...[Other Workers will be resumed 
   ║                    │         │           │             │         ║     till most 99% are waiting on 
   ║───lots of          │         │           │             │         ║     responses from their threads
   ║    short sleeps    ║◀──pushes response───────────────────────────┘
   ║                    ║         │           │             ║◀──pop───║ ...[block waiting for request]
   ║──pop(response)──◀─▶║         │           │             ║         │
   ║                    │         │           │             ║         │
   ║──saves─response───────────────────────◀─▶│             ║         │
   ║                    │         │           │             ║         │
   ║───resumes-next─"can_resume"─────────────▶┐             ║         │
   │                    │         │           ║             ║         │
   │                    │         ║◀──resume──┘             ║         │ ...[Resume passes response]
   │                    │         ║           │             ║         │ 
   │                    │         ║           │             ║         │ ...[Process Response]
```
**REPEATS TO HERE** - WHEN FIBER FINISHES, instead it:  
```text
 SCHEDULER        RESPONSE.Q    FIBER         WORKER        REQUEST.Q THREAD  
   │                    │         ║             │           ║         │ 
   │                    │         ║─deregister─▶║           ║         │
   │                    │         │             ║──close───▶║         │ 
   │                    │         │             ║           ║──nil───▶┐ 
   │                    │         │             ║           │         ║ ... [thread exists] 
   │                    │         │             ║──join────────────◀─▶┘ 
   │                    │         │             ║  ....... [worker removes 
   │                    │         │             ║           itself from registry]                     
   │                    │         ║◀──returns───┘                       
   │◀──returns─nil────────────────┘                                    
   │                    │                                             
```
When the last fiber finishes and the registry is empty, then the response queue is also removed
