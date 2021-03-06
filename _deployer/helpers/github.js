const axios = require("axios");
const cache = require('./cache');
const {GITHUB_USER_AGENT, GITHUB_PERSONAL_ACCESS_TOKEN, DEBUG} = process.env;

function getGithubAuthHeaders() {
    return {
        "Content-Type": "application/json",
        "User-Agent": GITHUB_USER_AGENT,
        Authorization: `Basic ${Buffer.from(GITHUB_USER_AGENT + ":" + GITHUB_PERSONAL_ACCESS_TOKEN).toString("base64")}`
    };
}

async function getBranches(url, headers) {
    let rawData = [];
    if (cache.hasOwnProperty(url) && cache[url].expires > new Date().getTime()) {
        rawData = cache[url].data;
    } else {
        let {data} = await axios.get(url, {headers});
        rawData = data;
        cache[url] = {
            expires: new Date().getTime() + 60000, //Cache for a minute
            data
        };
    }
    let branchNames = rawData.map(i => i.name || i.head.ref);
    branchNames.sort();
    return branchNames;
}

async function getPullRequestDetails(url, headers) {
    let branches = [];
    if (cache.hasOwnProperty(url) && cache[url].expires > new Date().getTime()) {
        branches = cache[url].data;
    } else {
        let {data} = await axios.get(url, {headers});
        branches = data;
    }
    let result = {};
    const urlRegexp = /\b((?:[a-z][\w-]+:(?:\/{1,3}|[a-z0-9%])|www\d{0,3}[.]|[a-z0-9.\-]+[.][a-z]{2,4}\/)(?:[^\s()<>]+|\(([^\s()<>]+|(\([^\s()<>]+\)))*\))+(?:\(([^\s()<>]+|(\([^\s()<>]+\)))*\)|[^\s`!()\[\]{};:'".,<>?«»“”‘’]))/gi;

    await Promise.all(branches.map(async branch => {
        //console.log(branch);
        let {
            head = {},
            labels = [],
            body = "",
            title = "",
            statuses_url = "",
            state = "",
            html_url: githubUrl = ""
        } = branch;
        //console.log(statuses_url);
        let {data} = await axios.get(statuses_url, {headers});
        // console.log(data);
        let {state: buildStatus, description: buildDescription, updated_at: lastBuild, target_url: buildUrl} = data.length > 0 ? data[0] : {};

        let {ref: branchName} = head;
        labels = labels.map(label => ({name: label.name, color: label.color}));
        let urls = (body.match(urlRegexp) || []).filter(
            url => typeof url === "string" && url.indexOf("asana") !== -1
        ).map(i => ({type: 'asana', url: i}));
        urls.splice(0, 0, {type: 'github', url: githubUrl});

        result[branchName] = {
            labels,
            state,
            githubUrl,
            branchName,
            urls,
            body,
            title, buildStatus, buildDescription, lastBuild, buildUrl
        };
    }));

    if (DEBUG) {
        console.log(result);
    }

    return result;
}

module.exports = {
    getBranches,
    getPullRequestDetails,
    getGithubAuthHeaders
};
