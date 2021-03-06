//
//  GitHubXCBotUtils.swift
//  Buildasaur
//
//  Created by Honza Dvorsky on 16/05/2015.
//  Copyright (c) 2015 Honza Dvorsky. All rights reserved.
//

import Foundation
import XcodeServerSDK
import BuildaGitServer
import BuildaUtils

extension HDGitHubXCBotSyncer {
    
    //MARK: Bot manipulation utils
    
    func cancelIntegrations(integrations: [Integration], completion: () -> ()) {
        
        integrations.mapVoidAsync({ (integration, itemCompletion) -> () in
            
            self.xcodeServer.cancelIntegration(integration.id, completion: { (success, error) -> () in
                if error != nil {
                    self.notifyError(error, context: "Failed to cancel integration \(integration.number)")
                } else {
                    Log.info("Successfully cancelled integration \(integration.number)")
                }
                itemCompletion()
            })
            
            }, completion: completion)
    }
    
    func deleteBot(bot: Bot, completion: () -> ()) {
        
        self.xcodeServer.deleteBot(bot.id, revision: bot.rev, completion: { (success, error) -> () in
            
            if error != nil {
                self.notifyError(error, context: "Failed to delete bot with name \(bot.name)")
            } else {
                Log.info("Successfully deleted bot \(bot.name)")
            }
            completion()
        })
    }
    
    private func createBotFromName(botName: String, branch: String, repo: Repo, completion: () -> ()) {
        
        /*
        synced bots must have a manual schedule, Builda tells the bot to reintegrate in case of a new commit.
        this has the advantage in cases when someone pushes 10 commits. if we were using Xcode Server's "On Commit"
        schedule, it'd schedule 10 integrations, which could take ages. Builda's logic instead only schedules one
        integration for the latest commit's SHA.
        
        even though this is desired behavior in this syncer, technically different syncers can have completely different
        logic. here I'm just explaining why "On Commit" schedule isn't generally a good idea for when managed by Builda.
        */
        let schedule = BotSchedule.manualBotSchedule()
        let template = self.currentBuildTemplate()
        
        //to handle forks
        let headOriginUrl = repo.repoUrlSSH
        let localProjectOriginUrl = self.localSource.projectURL!.absoluteString
        
        let project: LocalSource
        if headOriginUrl != localProjectOriginUrl {
            
            //we have a fork, duplicate the metadata with the fork's origin
            if let source = self.localSource.duplicateForForkAtOriginURL(headOriginUrl) {
                project = source
            } else {
                self.notifyError(Error.withInfo("Couldn't create a LocalSource for fork with origin at url \(headOriginUrl)"), context: "Creating a bot from a PR")
                completion()
                return
            }
        } else {
            //a normal PR in the same repo, no need to duplicate, just use the existing localSource
            project = self.localSource
        }
        
        let xcodeServer = self.xcodeServer
        
        XcodeServerSyncerUtils.createBotFromBuildTemplate(botName, template: template, project: project, branch: branch, scheduleOverride: schedule, xcodeServer: xcodeServer) { (bot, error) -> () in
            
            if error != nil {
                self.notifyError(error, context: "Failed to create bot with name \(botName)")
            }
            completion()
        }
    }
    
    func createBotFromPR(pr: PullRequest, completion: () -> ()) {
        
        let branchName = pr.head.ref
        let botName = BotNaming.nameForBotWithPR(pr, repoName: self.repoName()!)
        
        self.createBotFromName(botName, branch: branchName, repo: pr.head.repo, completion: completion)
    }
    
    func createBotFromBranch(branch: Branch, repo: Repo, completion: () -> ()) {
        
        let branchName = branch.name
        let botName = BotNaming.nameForBotWithBranch(branch, repoName: self.repoName()!)
        
        self.createBotFromName(botName, branch: branchName, repo: repo, completion: completion)
    }
    
    private func currentBuildTemplate() -> BuildTemplate! {
        
        if
            let preferredTemplateId = self.localSource.preferredTemplateId,
            let template = StorageManager.sharedInstance.buildTemplates.filter({ $0.uniqueId == preferredTemplateId }).first {
                return template
        }
        
        assertionFailure("Couldn't get the current build template, this syncer should NOT be running!")
        return nil
    }
}
