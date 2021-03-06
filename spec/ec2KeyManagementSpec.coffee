conf = require('../lib/config')
conf.AWS.PRIVATE_KEY_FILE = 'test-keyfile'
conf.AWS.SSH_USER = 'test-user'
ec2KeyManagement = require('../lib/ec2KeyManagement')
ec2Client = require('../lib/ec2Client')
Promise = require('pantheon-helpers/lib/promise')

describe 'setSSHKeys', () ->
  beforeEach () ->
    spyOn(ec2KeyManagement, 'exec').andCallFake((command) =>
      if this.sshFailConnect
        return Promise.reject({code: 1, signal: 0})

      return Promise.resolve()
    )
    spyOn(ec2Client, 'startInstances').andCallFake((aws_id) =>
      return Promise.resolve({State: {Name: 'running'}})
    )
    spyOn(ec2Client, 'stopInstances').andCallFake((aws_id) =>
      return Promise.resolve({State: {Name: 'halted'}})
    )
    spyOn(Promise, 'setTimeout').andCallFake((seconds) =>
      return Promise.resolve()
    )
    spyOn(ec2Client, 'getSingleInstance').andCallFake((aws_id) =>
      if this.awsFailConnect
        return Promise.reject("failed to connect")
      if this.awsHaltedInstance
        return Promise.resolve({State: {Name: 'halted'}})
      if this.awsPendingInstance
        return Promise.resolve({State: {Name: 'pending'}})
      else
        return Promise.resolve({State: {Name: 'running'}})
    )
    this.sshFailConnect = false
    this.awsFailConnect = false
    this.awsPendingInstance = false
    this.awsHaltedInstance = false
    this.instance = {aws_id: 'aws_id'}
    this.pubkeys = [
      'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCiTE9GnjEQeL4wMiqAsCJteX67PF6rleStq7PGBPSkXkiyodW4VhPq30vTdwxLRSPAp6yB2QaASjgbmLU8SkoBZER9JFMUCuqblq2Ngz1SUvzD2wnV2IjBnVR1uBY2BF2VKH3m3VbnHduXSlpXitjm8jcua22tlB1Vd2Qz22/sOvRk/zUmCyN6DYC0SyHG8njRigWLgQU9Ir62geksPam+aN7n/fZAKsE9vZkCLcN3qBkMFbPnliMurs5KtFbJlZLYSil5QtBNK3bfLPbpAK0aLz/zmASr7FSLsvOvB30FDyKb/3Qm0uE2LkIknHvd34KcxmGmPGlAWl6vDdRd5SF5 Username1@RandomHost1.company'
      'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCiTE9GnjEQeL4wMiqAsCJteX67PF6rleStq7PGBPSkXkiyodW4VhPq30vTdwxLRSPAp6yB2QaASjgbmLU8SkoBZER9JFMUCuqblq2Ngz1SUvzD2wnV2IjBnVR1uBY2BF2VKH3m3VbnHduXSlpXitjm8jcua22tlB1Vd2Qz22/sOvRk/zUmCyN6DYC0SyHG8njRigWLgQU9Ir62geksPam+aN7n/fZAKsE9vZkCLcN3qBkMFbPnliMurs5KtFbJlZLYSil5QtBNK3bfLPbpAK0aLz/zmASr7FSLsvOvB30FDyKb/3Qm0uE2LkIknHvd34KcxmGmPGlAWl6vDdRd5SF6 Username2@RandomHost2.company'
    ]

  it 'execs an ssh command to update the keys if everything goes right', (done) ->
    cut = ec2KeyManagement.setSSHKeys
    cut(this.instance, this.pubkeys).then(() ->
      expect(ec2KeyManagement.exec.calls.length).toEqual(1)
      done()
    ).catch(done)

  it 'resolves if everything goes right', (done) ->
    cut = ec2KeyManagement.setSSHKeys
    cut(this.instance, this.pubkeys).then(() ->
      expect(ec2KeyManagement.exec.calls.length).toEqual(1)
      done()
    ).catch(done)

  it 'retries 5 times and rejects if the SSHconnection fails', (done) ->
    cut = ec2KeyManagement.setSSHKeys
    this.sshFailConnect = true
    cut(this.instance, this.pubkeys).then(() =>
      done('Test failed, promise should have been rejected but was resolved')
    ).catch((err) =>
      expect(ec2KeyManagement.exec.calls.length).toEqual(5)
      done()
    )

  it 'execs ssh command if instance state is pending', (done) ->
    cut = ec2KeyManagement.setSSHKeys
    this.awsPendingInstance = true
    cut(this.instance, this.pubkeys).catch(() ->
      done('Test failed, promise should have been resolved but was rejected')
    ).then(() ->
      expect(ec2KeyManagement.exec.calls.length).toEqual(1)
      done()
    )

  it 'runs startInstances and stopInstances if the instance state is halted', (done) ->
    cut = ec2KeyManagement.setSSHKeys
    this.awsHaltedInstance = true
    cut(this.instance, this.pubkeys).then(() ->
      expect(ec2Client.getSingleInstance.calls.length).toEqual(1)
      expect(ec2Client.startInstances.calls.length).toEqual(1)
      expect(ec2Client.stopInstances.calls.length).toEqual(1)
      done()
    ).catch(done)

  it 'does not call startInstances or stopInstances if the instance is already running', (done) ->
    cut = ec2KeyManagement.setSSHKeys
    cut(this.instance, this.pubkeys).then(() ->
      expect(ec2Client.getSingleInstance.calls.length).toEqual(1)
      expect(ec2Client.startInstances.calls.length).toEqual(0)
      expect(ec2Client.stopInstances.calls.length).toEqual(0)
      done()
    ).catch(done)

  it 'does not call startInstances or stopInstances if the instance state is pending', (done) ->
    cut = ec2KeyManagement.setSSHKeys
    this.awsPendingInstance = true
    cut(this.instance, this.pubkeys).then(() ->
      expect(ec2Client.getSingleInstance.calls.length).toEqual(1)
      expect(ec2Client.startInstances.calls.length).toEqual(0)
      expect(ec2Client.stopInstances.calls.length).toEqual(0)
      done()
    ).catch(done)

  it 'eventually execs the ssh command if instance state is halted (after starting up the instance)', (done) ->
    cut = ec2KeyManagement.setSSHKeys
    this.awsHaltedInstance = true
    cut(this.instance, this.pubkeys).then(() ->
      expect(ec2KeyManagement.exec.calls.length).toEqual(1)
      done()
    ).catch(done)

  it 'fails if instance has no aws_id', (done) ->
    cut = ec2KeyManagement.setSSHKeys
    this.awsHaltedInstance = true
    this.instance.aws_id = undefined
    cut(this.instance, this.pubkeys).then(() ->
      done('Test failed, promise should have been rejected but was resolved')
    ).catch(() ->
      done()
    )

