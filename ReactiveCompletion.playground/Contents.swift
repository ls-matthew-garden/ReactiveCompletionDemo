import Combine
import RxCocoa
import RxSwift
import UIKit

// Setup helpers for networking, etc.
let disposeBag = DisposeBag()

let session: URLSession = .init(configuration: .default)
let request: URLRequest = URLRequest(url: URL(string: "https://swapi.dev/api/people/1")!)

public enum StarWarsError: Error {
    case noData
}

extension StarWarsError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .noData:
            return NSLocalizedString("No data", comment: "Request returned no data object")
        }
    }
}

struct Person: Codable {
    var name: String
}

extension Data {
    func person() -> Result<Person, Error> {
        let decoder = JSONDecoder()
        do {
            let person = try decoder.decode(Person.self, from: self)
            return .success(person)
            
        } catch let decodeError {
            return .failure(decodeError)
        }
    }
}

// Helpers for demonstrating chaining reactive events
var delay: Int = 3
let completeAfterDelay: () -> Completable = {
    return Completable.create(subscribe: { observer in
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(delay)) {
            observer(.completed)
        }
        return Disposables.create()
    })
}
let stringAfterDelay: (String) -> Single<String> = { value in
    return Single<String>.create(subscribe: { observer in
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(delay)) {
            observer(.success(value))
        }
        return Disposables.create()
    })
}
let maybeAfterDelay: (String) -> Maybe<String> = { value in
    return Maybe<String>.create(subscribe: { observer in
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(delay)) {
            observer(.success("Long ago in a galaxy far far away... \(value)"))
        }
        return Disposables.create()
    })
}
let emptyAfterDelay: (String) -> Maybe<String> = { value in
    return Maybe<String>.create(subscribe: { observer in
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(delay)) {
            observer(.completed)
        }
        return Disposables.create()
    })
}
let errorAfterDelay: () -> Maybe<String> = {
    return Maybe.create(subscribe: { observer in
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(delay)) {
            observer(.error(NSError(domain: "Reactive completions", code: 0, userInfo: nil)))
        }
        return Disposables.create()
    })
}

// Type that can fetch from swapi.dev and communicate the result using RxSwift
struct RxSwapiSession {
    
    let session: URLSession
    
    func fetchCompletable(_ request: URLRequest) -> Completable {
        return Completable.create(subscribe: { [session=self.session] observer in
            let dataTask = session.dataTask(with: request) { _, _, error in
                if let error = error {
                    observer(.error(error))
                    return
                }
                
                observer(.completed)
            }
            
            dataTask.resume()
            
            return Disposables.create {
                dataTask.cancel()
            }
        })
    }
    
    func fetchSingle(_ request: URLRequest) -> Single<String> {
        return Single.create(subscribe: { [session=self.session] observer in
            let dataTask = session.dataTask(with: request) { data, _, error in
                if let error = error {
                    observer(.error(error))
                    return
                }
                
                guard let data = data else {
                    observer(.error(StarWarsError.noData))
                    return
                }
                
                switch data.person() {
                case let .success(person):
                    observer(.success(person.name))
                    
                case let .failure(error):
                    observer(.error(error))
                }
            }
            
            dataTask.resume()
            
            return Disposables.create {
                dataTask.cancel()
            }
        })
    }
    
    func fetchMaybe(_ request: URLRequest) -> Maybe<String> {
        return Maybe.create(subscribe: { [session=self.session] observer in
            let dataTask = session.dataTask(with: request) { data, response, error in
                if let error = error {
                    observer(.error(error))
                    return
                }
                
                guard let data = data,
                      response != nil else {
                    observer(.completed)
                    return
                }
                
                switch data.person() {
                case let .success(person):
                    observer(.success(person.name))
                    
                case let .failure(error):
                    observer(.error(error))
                }
            }
            
            dataTask.resume()
            
            return Disposables.create {
                dataTask.cancel()
            }
        })
    }
}

let rxSession = RxSwapiSession(session: session)

rxSession.fetchCompletable(request)
    .andThen(Single<String>.just("It worked"))
    .catchError({ error in
        return .just("The force is not with us: \(error)")
    })
    .subscribe(onSuccess: { print("fetchCompletable: \($0)") })
    .disposed(by: disposeBag)

rxSession.fetchSingle(request)
    .subscribe(onSuccess: { value in
        print("fetchSingle: \(value)")
    }, onError: { error in
        print(error)
    })
    .disposed(by: disposeBag)

rxSession.fetchSingle(request)
    .flatMapMaybe(maybeAfterDelay)
    .ifEmpty(switchTo: maybeAfterDelay("Nobody"))
    .subscribe(onSuccess: { value in
        print("flatMapMaybe: \(value)")
    })
    .disposed(by: disposeBag)

// Do something similar using Combine

struct CombineSwapiSession {

    let session: URLSession
    
    func fetchSingle(_ request: URLRequest) -> Future<String, Error> {
        let future = Future<String, Error> { [session=self.session] promise in
            let dataTask = session.dataTask(with: request) { data, _, error in
                if let error = error {
                    promise(.failure(error))
                    return
                }
                
                guard let data = data else {
                    promise(.failure(StarWarsError.noData))
                    return
                }
                
                switch data.person() {
                case let .success(person):
                    promise(.success(person.name))
                    
                case let .failure(error):
                    promise(.failure(error))
                }
            }
            
            dataTask.resume()
        }
        
        return future
    }
}

let combineSwapiSession = CombineSwapiSession(session: session)

let cancellable = combineSwapiSession.fetchSingle(request)
    .sink(receiveCompletion: { _ in }, receiveValue: { value in
        print("Combine: \(value)")
    })
