// jupyterlab-m9: the M9 language for JupyterLab's editors.  It registers
// m9mode.js under the kernel's mimetype (text/x-m9) and name, so every
// cell of an M9 notebook -- and any .m9 file opened in JupyterLab --
// is highlighted by it.  The keywords are tools/edit/keywords.json,
// bundled at build time; runtime/test/highlight.sh holds the tokenizer
// to the lexer.

import { JupyterFrontEnd, JupyterFrontEndPlugin } from '@jupyterlab/application';
import { IEditorLanguageRegistry } from '@jupyterlab/codemirror';
import { LanguageSupport, StreamLanguage } from '@codemirror/language';
import keywords from '../../../edit/keywords.json';
import { makeM9 } from './m9mode.js';

const plugin: JupyterFrontEndPlugin<void> = {
  id: 'jupyterlab-m9:plugin',
  description: 'M9 syntax highlighting',
  autoStart: true,
  requires: [IEditorLanguageRegistry],
  activate: (app: JupyterFrontEnd, languages: IEditorLanguageRegistry) => {
    languages.addLanguage({
      name: 'm9',
      displayName: 'M9',
      mime: 'text/x-m9',
      extensions: ['m9'],
      load: async () =>
        new LanguageSupport(StreamLanguage.define(makeM9(Object.keys(keywords))))
    });
  }
};

export default plugin;
