/*
 * Copyright 2012-2025 the original author or authors.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      https://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

package org.springframework.samples.petclinic.system;

import org.springframework.beans.factory.ObjectProvider;
import org.springframework.boot.info.BuildProperties;
import org.springframework.boot.info.GitProperties;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.GetMapping;

@Controller
class WelcomeController {

	private final ObjectProvider<BuildProperties> buildProperties;

	private final ObjectProvider<GitProperties> gitProperties;

	WelcomeController(ObjectProvider<BuildProperties> buildProperties, ObjectProvider<GitProperties> gitProperties) {
		this.buildProperties = buildProperties;
		this.gitProperties = gitProperties;
	}

	@GetMapping("/")
	public String welcome(Model model) {
		BuildProperties build = this.buildProperties.getIfAvailable();
		if (build != null) {
			model.addAttribute("deploymentVersion", "Build " + build.getVersion());
			model.addAttribute("deploymentTime", "Built " + build.getTime());
		}

		GitProperties git = this.gitProperties.getIfAvailable();
		if (git != null) {
			String shortCommitId = git.getShortCommitId();
			if (shortCommitId != null) {
				model.addAttribute("deploymentRevision", "Commit " + shortCommitId);
			}
		}
		return "welcome";
	}

}
