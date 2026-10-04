"""Source-only CREATE/HOME reconciliation. No credentials, transport or imports with effects.

The caller supplies fresh, complete selected observations using the reviewed
observer and provider guard. This plan emits only one normal home operation;
it never emits an account creation or changes authentication/preferences.
Persist the returned claimed state durably BEFORE dispatching its operation.
"""
import copy
import math
import re
import uuid


class Refusal(RuntimeError):
    pass


def require(condition, reason):
    if not condition:
        raise Refusal(reason)


def account(value, name, uid, real_name, token, missing_allowed=False):
    keys = {'account', 'uid', 'home', 'homeOwner', 'homeKind', 'homeSymlink',
            'realName', 'admin', 'secureToken'}
    require(type(value) is dict and set(value) == keys, 'account schema unavailable')
    require(value['account'] == name and type(value['uid']) is int and value['uid'] == uid
            and value['home'] == '/Users/' + name and value['realName'] == real_name
            and value['admin'] is True and value['secureToken'] == token,
            'selected account changed')
    missing = (value['homeKind'] == 'absent' and value['homeOwner'] is None
               and value['homeSymlink'] is False)
    complete = (value['homeKind'] == 'directory' and type(value['homeOwner']) is int
                and value['homeOwner'] == uid and value['homeSymlink'] is False)
    require(complete or (missing_allowed and missing), 'home unsafe or unavailable')
    return complete


class CreateHome:
    """One owned creation journal, one home attempt, read-only reconciliation.

    Reconstruct from the separately persisted state after loss of a response.
    Claiming a mutation consumes it even if dispatch fails or returns no receipt.
    A missing home after a claimed attempt cannot cause another home command.
    """
    def __init__(self, original, original_sha, state=None):
        require(type(original_sha) is str and re.fullmatch('[0-9a-f]{64}', original_sha),
                'original journal provenance unavailable')
        self.original = copy.deepcopy(original)
        self.scope = self.original['scope']
        require(re.fullmatch('cbx_[0-9a-f]{12}', self.scope['lease']) is not None,
                'owned lease unavailable')
        require(str(uuid.UUID(self.scope['providerUUID'])) == self.scope['providerUUID']
                and self.scope['rootReleasedFreshScope'] is True
                and all(type(self.scope[k]) is int and self.scope[k] > 0
                        for k in ('expiresEpoch', 'bootEpoch', 'loginwindowPID')),
                'owned scope unavailable')
        self.name = 'keypathqa_' + self.scope['lease'][4:12]
        self.home = '/Users/' + self.name
        self.baseline = self.original['plan']['baseline']
        require(self.original['plan']['phase'] == 'creation-attempted'
                and type(self.original['pending']) is dict
                and self.original['pending']['action'] == 'create'
                and self.original['pending']['before'] == self.baseline
                and self.baseline['newAccount'] is None
                and self.baseline['uid502Accounts'] == []
                and self.baseline['newHomeAbsent'] is True,
                'sole claimed create and prior absence unavailable')
        account(self.baseline['qa'], 'keypathqa', 501, 'KeyPath QA', 'ENABLED')
        require(all(self.baseline[k] is None for k in
                    ('autoLoginUser', 'autologinToolUser', 'kcpassword')),
                'baseline authentication state not absent')
        initial = {'version': 1, 'originalJournalSHA256': original_sha,
                   'originalCreateAttempt': copy.deepcopy(self.original['pending']),
                   'originalCreateExit': None, 'phase': 'account-unobserved',
                   'homeAttempt': None, 'receipts': []}
        self.state = copy.deepcopy(initial if state is None else state)
        require(set(self.state) == set(initial) and self.state['version'] == 1
                and type(self.state['version']) is int
                and self.state['originalJournalSHA256'] == original_sha
                and self.state['originalCreateAttempt'] == initial['originalCreateAttempt']
                and self.state['originalCreateExit'] is None
                and self.state['phase'] in ('account-unobserved', 'account-created',
                                            'home-attempted', 'home-ready')
                and type(self.state['receipts']) is list,
                'reconciliation journal changed')
        require((self.state['homeAttempt'] is None and self.state['phase'] != 'home-attempted')
                or (type(self.state['homeAttempt']) is dict
                    and self.state['homeAttempt'].get('action') == 'create-home'
                    and self.state['phase'] in ('home-attempted', 'home-ready')),
                'home claim inconsistent')

    def check(self, provider, value, now):
        # Provider adapter emits selected fields only, after canonical inventory
        # ownership validation. A stage marker or guest return code is no authority.
        require(type(now) in (int, float) and math.isfinite(now)
                and type(provider) is dict
                and provider.get('ownedReady') is True
                and provider.get('lease') == self.scope['lease']
                and provider.get('providerUUID') == self.scope['providerUUID']
                and type(provider.get('expiresEpoch')) is int
                and provider['expiresEpoch'] == self.scope['expiresEpoch']
                and now < provider['expiresEpoch'], 'owned provider unavailable or expired')
        require(type(value) is dict and value.get('complete') is True
                and value.get('lease') == self.scope['lease']
                and value.get('providerUUID') == self.scope['providerUUID']
                and all(type(value.get(k)) is int and value[k] == expected for k, expected in
                        (('executorUID', 0), ('bootEpoch', self.scope['bootEpoch']),
                         ('consoleUID', 0), ('loginwindowUID', 0),
                         ('loginwindowPID', self.scope['loginwindowPID'])))
                and value.get('consoleAccount') == 'root'
                and value.get('usersRootSafe') is True and value.get('fileVaultOff') is True,
                'selected guest identity changed')
        require(all(type(value.get(k)) in (int, float) and math.isfinite(value[k])
                    for k in ('observedAt', 'hostReceivedAt', 'transportSeconds'))
                and 0 <= value['transportSeconds'] <= 35
                and -2 <= value['hostReceivedAt'] - value['observedAt'] <= 35
                and 0 <= now - value['hostReceivedAt'] <= 35,
                'selected guest evidence stale')
        require(all(value.get(k) == self.baseline[k] for k in
                    ('qa', 'autoLoginUser', 'autologinToolUser', 'kcpassword',
                     'otherLoginPreferencesSHA256', 'loginPreferencesFile')),
                'QA501 or login preferences changed')
        complete = account(value.get('newAccount'), self.name, 502,
                           'KeyPath Disposable ' + self.scope['lease'][4:12],
                           'DISABLED', missing_allowed=True)
        require(value.get('uid502Accounts') == [self.name]
                and value.get('newHomeAbsent') is (not complete),
                'account uniqueness or home evidence changed')
        return complete

    def reconcile(self, provider, value, now):
        complete = self.check(provider, value, now)
        require(self.state['phase'] != 'home-ready' or complete, 'accepted home disappeared')
        if complete:
            self.state['phase'] = 'home-ready'
        elif self.state['homeAttempt'] is None:
            self.state['phase'] = 'account-created'
        self.state['receipts'].append({'kind': 'observed-home-ready' if complete
                                      else 'observed-account-home-absent',
                                      'snapshot': copy.deepcopy(value)})
        return copy.deepcopy(self.state)

    def claim_home(self, provider, value, now):
        complete = self.check(provider, value, now)
        require(not complete and self.state['phase'] == 'account-created'
                and self.state['homeAttempt'] is None, 'home complete or already attempted; no replay')
        self.state['phase'] = 'home-attempted'
        self.state['homeAttempt'] = {'action': 'create-home', 'attemptID': str(uuid.uuid4()),
                                     'before': copy.deepcopy(value), 'commandExit': None}
        operation = {'argv': ['/usr/sbin/createhomedir', '-c', '-l', '-u', self.name],
                     'timeoutSeconds': 30, 'expectedBefore': copy.deepcopy(value)}
        return copy.deepcopy(self.state), operation


def complete_once(plan, provider, observe, clock, persist, dispatch):
    """Explicit adapters: persist must fsync private journal + parent namespace.

    Dispatch must guard the same selected lease and guest state again immediately
    before its one createhomedir syscall, and enforce the 30s bound. No transport
    retries are permitted. This function never treats a dispatch exit as proof.
    """
    selected_provider = provider()
    value = observe()
    state = plan.reconcile(selected_provider, value, clock())
    persist(state)
    if state['phase'] == 'home-ready':
        return state
    claimed, operation = plan.claim_home(selected_provider, value, clock())
    persist(claimed)  # A persistence failure prevents dispatch; claim stays consumed.
    current_provider = provider()
    current = observe()
    plan.check(current_provider, current, clock())
    def comparable(snapshot):
        return {k: v for k, v in snapshot.items()
                if k not in ('observedAt', 'hostReceivedAt', 'transportSeconds')}
    require(comparable(current) == comparable(value), 'pre-dispatch guest changed')
    dispatch(operation)  # Exactly once. Exception leaves the durable claim intact.
    after_provider = provider()
    after = observe()
    state = plan.reconcile(after_provider, after, clock())
    persist(state)
    require(state['phase'] == 'home-ready', 'home attempt unverified; no replay')
    return state
