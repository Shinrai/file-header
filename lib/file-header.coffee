# @Author: Guan Gui <guiguan>
# @Date:   2016-02-13T14:15:43+11:00
# @Email:  root@guiguan.net
# @Project: file-header
# @Filename: lib/file-header.coffee
# @Last modified by:   Nate Hyson <CLDMV> (nate+git-public@cldmv.net)
# @Last modified time: 2019-09-05T13:52:40-07:00



{CompositeDisposable} = require 'atom'
fs = require 'fs'
path = require 'path'
moment = require 'moment'

module.exports = FileHeader =
  config:
    realname:
      title: 'Real Name'
      order: 1
      description: 'Your last and first name. Leave empty to disable.'
      type: 'string'
      default: ''
    username:
      title: 'Username'
      order: 2
      description: 'Your username. Only allow chars from [A-Za-z0-9_]. Leave empty to disable.' + if process.env.USER then " Your current system username is <code>#{ process.env.USER }</code>." else ''
      type: 'string'
      default: ''
    email:
      title: 'Email Address'
      order: 3
      description: 'Your email address. Leave empty to disable.'
      type: 'string'
      default: ''
    enableProjectName:
      title: 'Enable Project Name'
      order: 4
      description: 'Whether to display Project Name in file header'
      type: 'boolean'
      default: true
    projectName:
      title: 'Project Name Default'
      order: 5
      description: 'Current project name. Leave empty to disable.'
      type: 'string'
      default: ''
    projectNameAuto:
      title: 'Auto Detect Project Name'
      order: 6
      description: 'Attempt to determine project name and display in file header'
      type: 'boolean'
      default: true
    enableFilename:
      title: 'Enable Filename'
      order: 7
      description: 'Whether to display filename in file header'
      type: 'boolean'
      default: false
    license:
      title: 'License'
      order: 8
      description: 'Your custom license text. Leave empty to disable.'
      type: 'string'
      default: ''
    copyright:
      title: 'Copyright'
      order: 9
      description: 'Your custom copyright text. Leave empty to disable.'
      type: 'string'
      default: ''
    configDirPath:
      title: 'Config Directory Path'
      order: 10
      description: 'Path to the directory that contains your customized File Header <code>lang-mapping.json</code> and <code>templates</code> directory. They will override default ones came with this package.'
      type: 'string'
      default: path.join(atom.config.configDirPath || path.dirname(atom.config.getUserConfigPath()), 'file-header')
    dateTimeFormat:
      title: 'Date Time Format'
      order: 11
      description: 'Custom Moment.js format string to be used for date times in file header. For example, <code>DD-MMM-YYYY</code>. Please refer to <a href="http://momentjs.com/docs/#/displaying/format/" target="_blank">Moment.js doc</a> for details.'
      type: 'string'
      default: ''
    useFileCreationTime:
      title: 'Use File Creation Time'
      order: 12
      description: 'Use file creation time instead of file header creation time for <code>{{create_time}}</code>.'
      type: 'boolean'
      default: true
    autoUpdateEnabled:
      title: 'Enable Auto Update'
      order: 13
      description: 'Auto update file header on saving. Otherwise, you can bind your own key to <code>file-header:update</code> for manually triggering update. This is a master switch for following related options.'
      type: 'boolean'
      default: true
    autoAddingHeaderOnNewFile:
      title: 'Enable Auto Adding Header on New File'
      order: 14
      description: 'Auto adding header for new files on creation. Files are considered new if they are empty.'
      type: 'boolean'
      default: true
    autoAddingHeaderOnSaving:
      title: 'Enable Auto Adding Header on Saving'
      order: 15
      description: 'Auto adding header for new files on saving. Files are considered new if they do not contain any field (e.g. <code>@(Demo) Author:</code>) defined in corresponding template file.'
      type: 'boolean'
      default: true
    ignoreListForAutoUpdateAndAddingHeader:
      title: 'Ignore List for Auto Update and Adding Header'
      order: 16
      description: 'List of language scopes to be ignored during auto update and auto adding header. For example, <code>source.gfm, source.css</code> will ignore GitHub Markdown and CSS files.'
      type: 'array'
      default: ['text.plain.null-grammar', 'text.html.basic', 'source.gfm']
      items:
        type: 'string'
    ignoreCaseInTemplateField:
      title: 'Ignore Case in Template Field'
      order: 17
      description: 'When ignored, the template field <code>@(Demo) Last modified by:</code> is considered equivalent to <code>@(Demo) Last Modified by:</code>.'
      type: 'boolean'
      default: true
    numOfEmptyLinesAfterNewHeader:
      title: 'Number of Empty Lines after New Header'
      order: 18
      description: 'Number of empty lines should be kept after a new header.'
      type: 'integer'
      default: 3
      minimum: 0

  subscriptions: null
  LAST_MODIFIED_BY: '{{last_modified_by}}'
  LAST_MODIFIED_TIME: '{{last_modified_time}}'
  LANG_MAPPING: 'lang-mapping.json'
  TEMPLATES: 'templates'

  activate: (state) ->
    if !state.notFirstTime
      @state = state
      @state.notFirstTime = true
      # if it is the first time this plugin is installed, we try to setup username
      # for the user
      username = atom.config.get 'file-header.username'
      # Lets see if a value is set. For some reason the state is being cleared. Usually happening after a restart of the OS.
      if !username or username == ''
        atom.config.set('file-header.username', process.env.USER ? '')

    # Events subscribed to in atom's system can be easily cleaned up
    # with a CompositeDisposable
    @subscriptions = new CompositeDisposable

    @subscriptions.add atom.config.onDidChange 'file-header.username', (event) =>
      if !event.newValue.match(/^\w*$/)
        # The timer is used to solve a problem that due to frequent updating,
        # sometimes the username shown in the config UI is not reverted to its
        # default value, though its underlying value is
        if @usernameDidChangeTimer
          clearTimeout(@usernameDidChangeTimer)
          @usernameDidChangeTimer = null
        @usernameDidChangeTimer = setTimeout(() =>
          atom.config.unset('file-header.username')
          atom.notifications.addError 'Invalid username', {detail: 'Please make sure it only contains characters from [A-Za-z0-9_]'}
        , 100)

    @subscriptions.add atom.config.observe 'file-header.autoUpdateEnabled', =>
      @updateToggleAutoUpdateEnabledStatusMenuItem()
      @updateToggleAutoUpdateEnabledStatusContextMenuItem()

    atom.workspace.observeTextEditors (editor) =>
      # now use `isEmpty` to determine if the file is just __created__
      # however, if an empty file is __open__, we will still try to
      # add the file header automatically
      if (atom.config.get 'file-header.autoUpdateEnabled', scope: (do editor.getRootScopeDescriptor)) && (atom.config.get 'file-header.autoAddingHeaderOnNewFile', scope: (do editor.getRootScopeDescriptor)) && editor.isEmpty() && !@isInIgnoreListForAutoUpdateAndAddingHeader(editor)
        headerTemplate = @getHeaderTemplate editor
        if headerTemplate
          buffer = editor.getBuffer()
          @addHeader(editor, buffer, headerTemplate)
          editor.save() if editor.getPath()

      editor.getBuffer().onWillSave =>
        return unless atom.config.get 'file-header.autoUpdateEnabled', scope: (do editor.getRootScopeDescriptor)
        @update()

    @subscriptions.add atom.commands.add 'atom-workspace',
      'file-header:add': => @add(true)
      'file-header:update': => @update(true)
      'file-header:toggleAutoUpdateEnabledStatus': => @toggleAutoUpdateEnabledStatus()

  serialize: ->
    @state

  deactivate: ->
    @subscriptions.dispose()

  getHeaderTemplate: (editor) ->
    configDirPath = atom.config.get('file-header.configDirPath', scope: (do editor.getRootScopeDescriptor))
    currScope = editor.getRootScopeDescriptor().getScopesArray()[0]
    templateFileName = null
    try
      # lookup user defined lang-mapping
      langMapping = JSON.parse(fs.readFileSync(path.join(configDirPath, @LANG_MAPPING), encoding: "utf8"))
      templateFileName = langMapping[currScope]
    if !templateFileName
      # fallback to default lang-mapping
      langMapping = JSON.parse(fs.readFileSync(path.join(__dirname, @LANG_MAPPING), encoding: "utf8"))
      templateFileName = langMapping[currScope]
    if !templateFileName
      return
    template = null
    try
      # lookup user defined template
      template = fs.readFileSync(path.join(configDirPath, @TEMPLATES, templateFileName), encoding: "utf8")
    if !template
      template = fs.readFileSync(path.join(__dirname, @TEMPLATES, templateFileName), encoding: "utf8")
    template

  getProject: (editor) ->
    return null unless editor.buffer.file
    projectName = document.querySelector('.atom-dock-content-wrapper.left .tool-panel.tree-view .project-root-header span')
    return null unless projectName
    projectPath = projectName.getAttribute('data-path')
    return null unless projectPath
    project =
      name: projectName.getAttribute('data-name')
      path: projectPath
    project

  getFilePathName: (editor) ->
    return null unless editor.buffer.file
    project = @getProject(editor)
    return editor.buffer.file.getBaseName() unless project
    filePath = editor.buffer.file.path
    filePathTest = filePath.substring(0, project.path.length)
    return editor.buffer.file.getBaseName() unless (project.path == filePathTest)
    filePath = filePath.substring(project.path.length + 1)
    filePath = filePath.replace(/\\/g, '/')
    filePath

  isPartofCurrentProject: (editor) ->
    return null unless editor.buffer.file
    project = @getProject(editor)
    return null unless project
    filePath = editor.buffer.file.path
    filePathTest = filePath.substring(0, project.path.length)
    return null unless (project.path == filePathTest)
    return true

  getProjectName: (editor) ->
    return null unless editor.buffer.file
    # repository = atom.project.getRepositoryForDirectory('/path/to/project');
    projectNameSetting = atom.config.get 'file-header.projectName', scope: (do editor.getRootScopeDescriptor)
    project = @getProject(editor)
    return projectNameSetting unless project
    projectNameAutoSetting = atom.config.get 'file-header.projectNameAuto', scope: (do editor.getRootScopeDescriptor)
    return projectNameSetting unless project
    return projectNameSetting unless @isPartofCurrentProject(editor)
    project.name

  getConfigData: (editor) ->
    return null unless editor
    realname = atom.config.get 'file-header.realname', scope: (do editor.getRootScopeDescriptor)
    username = atom.config.get 'file-header.username', scope: (do editor.getRootScopeDescriptor)
    email = atom.config.get 'file-header.email', scope: (do editor.getRootScopeDescriptor)
    if realname
      author = realname
      if username
        author += " <#{ username }>"
    else
      author = username
    byName = author
    if email
      byName += " (#{ email })"
    configData =
      realname: realname
      username: username
      email: email
      author: author
      byName: byName
    configData

  getCopyright: (editor) ->
    return null unless editor
    copyright = atom.config.get 'file-header.copyright', scope: (do editor.getRootScopeDescriptor)
    return null unless copyright
    # re = new RegExp("%([a-zA-Z]+)(?:\b|\r\n|\r|\n|\s)", 'g')
    # The above SHOULD work. But for some reason it doesn't. So lets go old school here.
    re = /%([a-zA-Z]+)(?:\b|\r\n|\r|\n|\s)/g;

    while m = re.exec(copyright)
      # This is necessary to avoid infinite loops with zero-width matches
      if m.index == re.lastIndex
        re.lastIndex++
      anchor = m[0]
      format = m[1]
      parsed = moment().format(format);
      if moment(parsed, format, true).isValid()
        copyright = copyright.replace(anchor, parsed)
    copyright

  getNewHeader: (editor, headerTemplate) ->
    return null unless headerTemplate
    return null unless editor
    configData = @getConfigData(editor)

    if configData.author
      # fill placeholder {{author}}
      headerTemplate = headerTemplate.replace(/\{\{author\}\}/g, configData.author)
    dateTimeFormat = atom.config.get('file-header.dateTimeFormat', scope: (do editor.getRootScopeDescriptor))
    currTimeStr = moment().format(dateTimeFormat)
    creationTime = currTimeStr
    # fill placeholder {{create_time}}
    if atom.config.get('file-header.useFileCreationTime', scope: (do editor.getRootScopeDescriptor))
      # try to retrieve creation time from current file meta data, otherwise use current time
      try
        currFilePath = editor.getPath()
        creationTime = moment(fs.statSync(currFilePath).birthtime.getTime()).format(dateTimeFormat)
    headerTemplate = headerTemplate.replace(new RegExp("#{ @escapeRegExp('{{create_time}}') }", 'g'), creationTime)
    # fill placeholder {{last_modified_time}}
    headerTemplate = headerTemplate.replace(new RegExp("#{ @escapeRegExp(@LAST_MODIFIED_TIME) }", 'g'), currTimeStr)

    if configData.email
      # fill placeholder {{email}}
      headerTemplate = headerTemplate.replace(/\{\{email\}\}/g, configData.email)
    if configData.byName
      # fill placeholder {{last_modified_by}}
      headerTemplate = headerTemplate.replace(new RegExp(@escapeRegExp(@LAST_MODIFIED_BY), 'g'), configData.byName)

    projectName = if (atom.config.get 'file-header.enableProjectName', scope: (do editor.getRootScopeDescriptor)) then @getProjectName(editor)
    if projectName
      # fill placeholder {{project_name}}
      headerTemplate = headerTemplate.replace(/\{\{project_name\}\}/g, projectName)

    license = atom.config.get 'file-header.license', scope: (do editor.getRootScopeDescriptor)
    if license
      # fill placeholder {{license}}
      headerTemplate = headerTemplate.replace(/\{\{license\}\}/g, license)

    filename = if (atom.config.get 'file-header.enableFilename', scope: (do editor.getRootScopeDescriptor)) then @getFilePathName(editor)
    if filename
      # fill placeholder {{filename}}
      headerTemplate = headerTemplate.replace(/\{\{filename\}\}/g, filename)

    copyright = @getCopyright(editor)
    if copyright
      # fill placeholder {{copyright}}
      headerTemplate = headerTemplate.replace(/\{\{copyright\}\}/g, copyright)

    # remove header lines with empty placeholders
    return headerTemplate = headerTemplate.replace(/^.*\{\{\w+\}\}(?:\r\n|\r|\n)/gm, '')

  escapeRegExp: (str) ->
    str.replace(/[\-\[\]\/\{\}\(\)\*\+\?\.\\\^\$\|]/g, "\\$&")

  # We consider a source file to have a file header if any placeholder line in
  # the corresponding header template is presented
  hasHeader: (editor, buffer, headerTemplate) ->
    # these placeholder preambles are used as anchor points in source code scanning
    if !(preambles = headerTemplate.match(/@[^:]+:/g))
      return false
    preambles = preambles.map(@escapeRegExp)
    re = new RegExp(preambles.join('|'), if atom.config.get('file-header.ignoreCaseInTemplateField', scope: (do editor.getRootScopeDescriptor)) then 'gi' else 'g')
    hasMatch = false
    buffer.scan(re, (result) =>
      hasMatch = true
      result.stop()
    )
    hasMatch

  updateField: (editor, placeholder, headerTemplate, buffer, newValue) ->
    escaptedPlaceholder = @escapeRegExp(placeholder)
    re = new RegExp(".*(@[^:]+:).*#{ escaptedPlaceholder }.*(?:\r\n|\r|\n)", 'g')
    # find anchor point and line in current template
    while match = re.exec(headerTemplate)
      anchor = match[1]
      newLine = match[0]
      # inject new value
      newLine = newLine.replace(new RegExp(escaptedPlaceholder, 'g'), newValue)
      # find and replace line in current buffer
      reB = new RegExp(".*#{ @escapeRegExp(anchor) }.*(?:\r\n|\r|\n)", if atom.config.get('file-header.ignoreCaseInTemplateField', scope: (do editor.getRootScopeDescriptor)) then 'gi' else 'g')
      buffer.scan(reB, (result) =>
        result.replace(newLine)
      )

  update: (manual = false) ->
    return unless editor = atom.workspace.getActiveTextEditor()
    return unless manual || !@isInIgnoreListForAutoUpdateAndAddingHeader(editor)
    buffer = editor.getBuffer()
    return unless headerTemplate = @getHeaderTemplate editor

    lastCheckpoint = buffer.createCheckpoint()
    history = buffer.historyProvider || buffer.history || buffer.getHistory()
    undoStackLen = history.undoStack.length
    if undoStackLen > 1
      # move checkpoint to before last transaction
      lastTranscationIdx = undoStackLen - 2
      lastCheckpointIdx = undoStackLen - 1
      lastTranscation = history.undoStack[lastTranscationIdx]
      history.undoStack[lastTranscationIdx] = history.undoStack[lastCheckpointIdx]
      history.undoStack[lastCheckpointIdx] = lastTranscation

    if @hasHeader(editor, buffer, headerTemplate)
      # update {{last_modified_by}}
  	  configData = @getConfigData(editor)
  	  @updateField editor, @LAST_MODIFIED_BY, headerTemplate, buffer, configData.byName

      # update {{last_modified_time}}
  	  @updateField editor, @LAST_MODIFIED_TIME, headerTemplate, buffer, moment().format(atom.config.get('file-header.dateTimeFormat', scope: (do editor.getRootScopeDescriptor)))
    else if atom.config.get('file-header.autoAddingHeaderOnSaving', scope: (do editor.getRootScopeDescriptor))
      @addHeader(editor, buffer, headerTemplate)

    buffer.groupChangesSinceCheckpoint(lastCheckpoint)

  addHeader: (editor, buffer, headerTemplate) ->
    return unless newHeader = @getNewHeader editor, headerTemplate
    newHeader += @getCurrentFileLineEnding(buffer).repeat(atom.config.get('file-header.numOfEmptyLinesAfterNewHeader', scope: (do editor.getRootScopeDescriptor)))
    # remove leading empty lines
    buffer.scan(/\s*(?:\r\n|\r|\n)(?=\S)/, (result) =>
      if result.range.start.isEqual([0, 0])
        result.replace('')
      result.stop()
    )

    [point, newHeader] = @execPreAddHeaderHooks editor, buffer, newHeader
    buffer.insert(point, newHeader, normalizeLineEndings: true)

  getDefaultLineEnding: ->
    switch atom.config.get('line-ending-selector.defaultLineEnding')
      when 'LF' then return '\n'
      when 'CRLF' then return '\r\n'
      else return if process.platform is 'win32' then '\r\n' else '\n'

  getCurrentFileLineEnding: (buffer) ->
    lineEnding = buffer.lineEndingForRow(0)
    if lineEnding is ''
      return @getDefaultLineEnding()
    return lineEnding

  execPreAddHeaderHooks: (editor, buffer, newHeader) ->
    point = [0, 0]
    if editor.getRootScopeDescriptor().getScopesArray()[0] is 'text.html.php'
      buffer.scan(/^(<\u003Fphp)|^(<\u003f)/, (result) =>
        point = result.range.start
        point.row += 1
        result.stop();
      )
      if point[0] is 0 and point[1] is 0
        # <?php or <? is not presented in current file, add <?php
        newHeader = "<?php#{@getCurrentFileLineEnding buffer}#{newHeader}"
    return [point, newHeader]

  add: (manual = false) ->
    return unless editor = atom.workspace.getActiveTextEditor()
    return unless manual || !@isInIgnoreListForAutoUpdateAndAddingHeader(editor)
    buffer = editor.getBuffer()
    return unless headerTemplate = @getHeaderTemplate editor
    @addHeader(editor, buffer, headerTemplate) unless @hasHeader(editor, buffer, headerTemplate)

  isInIgnoreListForAutoUpdateAndAddingHeader: (editor) ->
    currScope = editor.getRootScopeDescriptor().getScopesArray()[0]
    currScope in atom.config.get 'file-header.ignoreListForAutoUpdateAndAddingHeader', scope: (do editor.getRootScopeDescriptor)

  updateToggleAutoUpdateEnabledStatusMenuItem: ->
    packages = null
    for item in atom.menu.template
      if item.label is 'Packages'
        packages = item
        break
    return unless packages
    fileHeader = null
    for item in packages.submenu
     if item.label is 'File Header'
       fileHeader = item
       break
    return unless fileHeader
    toggle = null
    for item in fileHeader.submenu
      if item.command is 'file-header:toggleAutoUpdateEnabledStatus'
        toggle = item
        break
    return unless toggle
    toggle.label = if atom.config.get('file-header.autoUpdateEnabled') then 'Disable Auto Update' else 'Enable Auto Update'
    atom.menu.update()

  updateToggleAutoUpdateEnabledStatusContextMenuItem: ->
    fileHeader = null
    for item in atom.contextMenu.itemSets
      return unless item.items.length > 0
      subItem = item.items[0]
      if subItem.label is 'File Header'
        fileHeader = subItem
        break
    return unless fileHeader
    toggle = null
    for item in fileHeader.submenu
      if item.command is 'file-header:toggleAutoUpdateEnabledStatus'
        toggle = item
        break
    return unless toggle
    toggle.label = if atom.config.get('file-header.autoUpdateEnabled') then 'Disable Auto Update' else 'Enable Auto Update'

  toggleAutoUpdateEnabledStatus: ->
    atom.config.set('file-header.autoUpdateEnabled', !atom.config.get('file-header.autoUpdateEnabled'))
