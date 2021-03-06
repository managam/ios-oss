import KsApi
import LiveStream
import Prelude
import ReactiveSwift
import Result

public protocol ProjectPamphletContentViewModelInputs {
  func configureWith(project: Project, liveStreamEvents: [LiveStreamEvent])
  func tappedComments()
  func tapped(liveStreamEvent: LiveStreamEvent)
  func tappedPledgeAnyAmount()
  func tapped(rewardOrBacking: Either<Reward, Backing>)
  func tappedUpdates()
  func viewDidAppear(animated: Bool)
  func viewDidLoad()
  func viewWillAppear(animated: Bool)
}

public protocol ProjectPamphletContentViewModelOutputs {
  var goToBacking: Signal<Project, NoError> { get }
  var goToComments: Signal<Project, NoError> { get }
  var goToLiveStream: Signal<(Project, LiveStreamEvent), NoError> { get }
  var goToLiveStreamCountdown: Signal<(Project, LiveStreamEvent), NoError> { get }
  var goToRewardPledge: Signal<(Project, Reward), NoError> { get }
  var goToUpdates: Signal<Project, NoError> { get }
  var loadMinimalProjectIntoDataSource: Signal<Project, NoError> { get }
  var loadProjectAndLiveStreamsIntoDataSource: Signal<(Project, [LiveStreamEvent]), NoError> { get }
}

public protocol ProjectPamphletContentViewModelType {
  var inputs: ProjectPamphletContentViewModelInputs { get }
  var outputs: ProjectPamphletContentViewModelOutputs { get }
}

public final class ProjectPamphletContentViewModel: ProjectPamphletContentViewModelType,
ProjectPamphletContentViewModelInputs, ProjectPamphletContentViewModelOutputs {

  public init() {
    let projectAndLiveStreamEvents = Signal.combineLatest(
      self.configDataProperty.signal.skipNil(),
      self.viewDidLoadProperty.signal
      )
      .map(first)

    let project = projectAndLiveStreamEvents.map(first)

    let loadDataSourceOnSwipeCompletion = self.viewDidAppearAnimatedProperty.signal
      .filter(isTrue)
      .ignoreValues()
      .flatMap { _ in
        // NB: skip a run loop to ease the initial rendering of the cells and the swipe animation
        SignalProducer(value: ()).delay(0, on: AppEnvironment.current.scheduler)
    }

    let loadDataSourceOnModalCompletion = self.viewWillAppearAnimatedProperty.signal
      .filter(isFalse)
      .ignoreValues()

    let timeToLoadDataSource = Signal.merge(
      loadDataSourceOnSwipeCompletion,
      loadDataSourceOnModalCompletion
      )
      .take(first: 1)

    self.loadProjectAndLiveStreamsIntoDataSource = Signal.combineLatest(
      projectAndLiveStreamEvents,
      timeToLoadDataSource
      )
      .map { projectAndLive, _ in (projectAndLive.0, projectAndLive.1) }

    self.loadMinimalProjectIntoDataSource = project
      .takePairWhen(self.viewWillAppearAnimatedProperty.signal)
      .take(first: 1)
      .filter(second)
      .map(first)

    let rewardOrBackingTapped = Signal.merge(
      self.tappedRewardOrBackingProperty.signal.skipNil(),
      self.tappedPledgeAnyAmountProperty.signal.mapConst(.left(Reward.noReward))
    )

    self.goToRewardPledge = project
      .takePairWhen(rewardOrBackingTapped)
      .map(goToRewardPledgeData(forProject:rewardOrBacking:))
      .skipNil()

    self.goToBacking = project
      .takePairWhen(rewardOrBackingTapped)
      .map(goToBackingData(forProject:rewardOrBacking:))
      .skipNil()

    self.goToComments = project
      .takeWhen(self.tappedCommentsProperty.signal)

    self.goToUpdates = project
      .takeWhen(self.tappedUpdatesProperty.signal)

    self.goToLiveStream = project
      .takePairWhen(
        self.tappedLiveStreamProperty.signal.skipNil()
          .filter(shouldGoToLiveStream(withLiveStreamEvent:))
    )

    self.goToLiveStreamCountdown = project
      .takePairWhen(
        self.tappedLiveStreamProperty.signal.skipNil()
          .filter({ !shouldGoToLiveStream(withLiveStreamEvent: $0) })
    )
  }

  fileprivate let configDataProperty = MutableProperty<(Project, [LiveStreamEvent])?>(nil)
  public func configureWith(project: Project, liveStreamEvents: [LiveStreamEvent]) {
    self.configDataProperty.value = (project, liveStreamEvents)
  }

  fileprivate let tappedCommentsProperty = MutableProperty()
  public func tappedComments() {
    self.tappedCommentsProperty.value = ()
  }

  private let tappedLiveStreamProperty = MutableProperty<LiveStreamEvent?>(nil)
  public func tapped(liveStreamEvent: LiveStreamEvent) {
    self.tappedLiveStreamProperty.value = liveStreamEvent
  }

  fileprivate let tappedPledgeAnyAmountProperty = MutableProperty()
  public func tappedPledgeAnyAmount() {
    self.tappedPledgeAnyAmountProperty.value = ()
  }

  fileprivate let tappedRewardOrBackingProperty = MutableProperty<Either<Reward, Backing>?>(nil)
  public func tapped(rewardOrBacking: Either<Reward, Backing>) {
    self.tappedRewardOrBackingProperty.value = rewardOrBacking
  }

  fileprivate let tappedUpdatesProperty = MutableProperty()
  public func tappedUpdates() {
    self.tappedUpdatesProperty.value = ()
  }

  fileprivate let viewDidAppearAnimatedProperty = MutableProperty(false)
  public func viewDidAppear(animated: Bool) {
    self.viewDidAppearAnimatedProperty.value = animated
  }

  fileprivate let viewDidLoadProperty = MutableProperty()
  public func viewDidLoad() {
    self.viewDidLoadProperty.value = ()
  }

  fileprivate let viewWillAppearAnimatedProperty = MutableProperty(false)
  public func viewWillAppear(animated: Bool) {
    self.viewWillAppearAnimatedProperty.value = animated
  }

  public let goToBacking: Signal<Project, NoError>
  public let goToComments: Signal<Project, NoError>
  public let goToLiveStream: Signal<(Project, LiveStreamEvent), NoError>
  public let goToLiveStreamCountdown: Signal<(Project, LiveStreamEvent), NoError>
  public let goToRewardPledge: Signal<(Project, Reward), NoError>
  public let goToUpdates: Signal<Project, NoError>
  public let loadMinimalProjectIntoDataSource: Signal<Project, NoError>
  public let loadProjectAndLiveStreamsIntoDataSource: Signal<(Project, [LiveStreamEvent]), NoError>

  public var inputs: ProjectPamphletContentViewModelInputs { return self }
  public var outputs: ProjectPamphletContentViewModelOutputs { return self }
}

private func reward(forBacking backing: Backing, inProject project: Project) -> Reward? {

  return backing.reward
    ?? project.rewards.filter { $0.id == backing.rewardId }.first
    ?? Reward.noReward
}

private func shouldGoToLiveStream(withLiveStreamEvent liveStreamEvent: LiveStreamEvent) -> Bool {
  return liveStreamEvent.liveNow
    || liveStreamEvent.startDate < AppEnvironment.current.dateType.init().date
}

private func goToRewardPledgeData(forProject project: Project, rewardOrBacking: Either<Reward, Backing>)
  -> (Project, Reward)? {

    guard project.state == .live else { return nil }

    switch rewardOrBacking {
    case let .left(reward):
      guard reward.remaining != .some(0) else { return nil }
      return (project, reward)

    case let .right(backing):
      guard let reward = reward(forBacking: backing, inProject: project) else { return nil }

      return (project, reward)
    }
}

private func goToBackingData(forProject project: Project, rewardOrBacking: Either<Reward, Backing>)
  -> Project? {

    guard project.state != .live && rewardOrBacking.right != nil else {
      return nil
    }

    return project
}
