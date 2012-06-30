# Core Data Examples

This repository includes code demonstrating asynchronous importing and searching with Core Data.

This example was created to accompany [a presentation](http://wbyoung.github.com/core_data.pdf). There are various issues with it including but not limited to those below. Please thoroughly test anything you use from this example before using it in production.

### Issues

 * There is no error handling
 * Refreshed and reset objects are not handled in asynchronous searching
 * Duplicates could be added in the asynchronous search if an object is updated & inserted & deleted during the search

Feel free to contact me with questions or concerns regarding this example.
